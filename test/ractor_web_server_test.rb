# frozen_string_literal: true

require "test_helper"

class RactorWebServerTest < Test::Unit::TestCase
  test "VERSION" do
    assert do
      ::RactorWebServer.const_defined?(:VERSION)
    end
  end
end
