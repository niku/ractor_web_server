# frozen_string_literal: true

# rubocop:disable Layout/LineLength

require "test_helper"
require "ractor_web_server"
require "stringio"
require "socket"
require "net/http"
module RactorWebServer
  class ServerTest < Test::Unit::TestCase
    class ServerInterfaceTests < self
      test "server starts and listens on a port" do
        subscriber = Ractor::Port.new
        app = Ractor.make_shareable(nil.instance_eval { proc { [200, { "Content-Type" => "text/plain" }, ["Hello World!"]] } })
        port = 45_893 # assuming this port is available at testing environment
        server = RactorWebServer::Server.new(app: app, port: port, subscribers: { server_started: subscriber })
        Ractor.new(server, &:run)
        subscriber.receive => { event: :server_started, data: { actual_port_number: } }
        assert_equal port, actual_port_number
      end

      test "server starts and listens on an ephemeral port if given port is 0" do
        subscriber = Ractor::Port.new
        app = Ractor.make_shareable(nil.instance_eval { proc { [200, { "Content-Type" => "text/plain" }, ["Hello World!"]] } })
        port = 0
        server = RactorWebServer::Server.new(app: app, port: port, subscribers: { server_started: subscriber })
        Ractor.new(server, &:run)
        subscriber.receive => { event: :server_started, data: { actual_port_number: } }
        assert_includes (1024..65_535), actual_port_number,
                        "Expected actual port number to be in the ephemeral range(1024-65535), got #{actual_port_number}"
      end

      test "server responds to HTTP requests" do
        subscriber = Ractor::Port.new
        app = Ractor.make_shareable(nil.instance_eval { proc { [200, { "Content-Type" => "text/plain" }, ["Hello World!"]] } })
        port = 0
        server = RactorWebServer::Server.new(app: app, port: port, subscribers: { server_started: subscriber })
        Ractor.new(server, &:run)
        subscriber.receive => { event: :server_started, data: { actual_port_number: } }
        socket = TCPSocket.open("localhost", actual_port_number, open_timeout: 10)
        socket.write("GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        response = socket.read
        socket.close
        assert_match(%r{HTTP/1\.1 200 OK}, response, "Expected to get a HTTP response")
      end
    end
  end
end

# rubocop:enable all
