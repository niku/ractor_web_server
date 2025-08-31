# frozen_string_literal: true

require "test_helper"
require "ractor_web_server"

class RactorWebServer::RackupHandlerTest < Test::Unit::TestCase
  def setup
    @klass = Class.new do
      class << self
        include ::RactorWebServer::RackupHandler
      end
    end
  end

  def test_run
    subscriber = Ractor::Port.new

    Ractor.new(@klass, subscriber) do |klass, subscriber|
      app = Ractor.make_shareable(nil.instance_eval do
        proc {
          [200, { "Content-Type" => "text/plain" }, ["Hello World!"]]
        }
      end)
      subscribers = { server_started: subscriber }
      klass.run(app, Port: 0, subscribers: subscribers)
    end

    subscriber.receive => { event: :server_started, data: { actual_port_number: } }

    assert_nothing_raised do
      require "net/http"
      response = Net::HTTP.get_response("localhost", "/", actual_port_number)
      assert_equal "200", response.code
      assert_equal "Hello World!", response.body
    end
  end
end
