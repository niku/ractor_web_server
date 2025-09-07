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

class Rackup::Handler::RactorWebServerTest < Test::Unit::TestCase
  TOP_PAGE = "Top Page"
  NOT_FOUND = "Not Found"

  test "::Rackup::Handler::RactorWebServer runs properly" do
    Ractor.new do
      app = Rack::Builder.new do
        process = nil.instance_eval do
          proc { |env|
            case env["PATH_INFO"].split("/")
            in [] # /
              [200, {}, [TOP_PAGE]]
            else
              [404, {}, [NOT_FOUND]]
            end
          }
        end
        use Rack::CommonLogger
        use Rack::Lint
        run process
      end

      ::Rackup::Handler::RactorWebServer.run(app)
    end

    assert_equal TOP_PAGE, ::Net::HTTP.get(URI.parse("http://localhost:8080/"))
    assert_equal NOT_FOUND, ::Net::HTTP.get(URI.parse("http://localhost:8080/aaaa"))
  end
end
