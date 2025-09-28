# frozen_string_literal: true

require "socket"
require "stringio"
require "webrick"
require_relative "rackup_handler"

# Workaround to avoid a Ractor::IsolationError
[
  WEBrick::HTTPUtils::HEADER_CLASSES,
  WEBrick::HTTPStatus::StatusMessage,
  WEBrick::Config::HTTP,
  Rack::ContentLength::STATUS_WITH_NO_ENTITY_BODY,
  Rack::Lint::Wrapper::BODY_METHODS,
  Rack::Request.ip_filter,
  Rack::Request.forwarded_priority
].each { |constant| Ractor.make_shareable(constant) }

module RactorWebServer
  class Server
    attr_reader :port

    def initialize(app:, subscribers:, port: 8080)
      # If a Rack::Builder instance was provided, finalize it first so we
      # don't try to make the builder (with its internal procs capturing
      # unshareable locals like `args`) shareable.
      app = app.to_app if app.respond_to?(:to_app)
      Ractor.make_shareable(app)
      raise("app must be a Ractor sharable object") unless Ractor.shareable?(app)
      raise("app must be a Ractor callable object") unless app.respond_to?(:call)

      @port = port
      @app = app
      @subscribers = (subscribers || {}).transform_values { |v| Array(v) }
    end

    def run
      tcp_server = TCPServer.new(@port)
      actual_port_number = tcp_server.addr[1] # Get the actual port number assigned by the OS

      emit(:server_started, actual_port_number: actual_port_number, tcp_server: tcp_server)

      Socket.accept_loop(tcp_server) do |connection|
        emit(:connection_accepted, connection: connection)

        r = Ractor.new(@app) do |app|
          conn = Ractor.receive
          # Causes Ractor::IsolationError unless RequestTimeout: nil is merged into the config.
          # Error: 'Singleton::SingletonClassMethods#instance': cannot access unshareable values from instance variables of classes/modules in non-main Ractors.
          # RequestTimeout: nil skips the timeout check in WEBrick::Utils.timeout
          req = WEBrick::HTTPRequest.new(WEBrick::Config::HTTP.merge(RequestTimeout: nil))
          req.parse(conn)

          env = req.meta_vars
          env.delete_if { |_, v| v.nil? } # Some env value (e.g. env["REMOTE_USER"]) are nil. Rack need values as string
          env.update(
            ::Rack::RACK_ERRORS => StringIO.new,
            ::Rack::RACK_URL_SCHEME => %w[yes on 1].include?(env[::Rack::HTTPS]) ? "https" : "http"
          )

          status, _, body = app.call(env)

          res = WEBrick::HTTPResponse.new(WEBrick::Config::HTTP)
          res.status = status
          body.each { |part| res.body << part }

          res.send_response(conn)
          conn.flush
        ensure
          conn&.close
        end
        r.send(connection, move: true)
      end
    rescue StandardError => e
      emit(:server_error, message: e.message, backtrace: e.backtrace)
    ensure
      emit(:server_stopping, tcp_server: tcp_server)
      tcp_server&.close
      emit(:server_stopped)
    end

    def subscribe(event, notifier)
      return if @subscribers[event]&.include?(notifier)

      @subscribers[event] ||= []
      @subscribers[event] << notifier
      nil
    end

    def unsubscribe(event, notifier)
      return unless @subscribers[event]

      @subscribers[event].delete(notifier)
      @subscribers.delete(event) if @subscribers[event].empty?
      nil
    end

    private

    # Send notification to the notifier if one is configured
    # @param event [Symbol] The event name
    # @param data [Hash] Event data to pass to the notifier
    def emit(event, data = {})
      return unless @subscribers[event]

      @subscribers[event].each do |subscriber|
        subscriber.send({ event: event, data: data }.freeze)
      end
    end
  end
end
