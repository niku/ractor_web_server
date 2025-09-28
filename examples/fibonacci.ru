# frozen_string_literal: true

require_relative "../lib/ractor_web_server"

class App
  def call(env)
    case env["PATH_INFO"].match(%r{^/(?<value>\d+)$})
    in { value: value }
      n = value.to_i
      v = fibonacci(n).to_s
      [200, {}, [v]]
    else
      [404, {}, ["Not Found"]]
    end
  end

  def fibonacci(n)
    return n if n < 2

    fibonacci(n - 1) + fibonacci(n - 2)
  end
end

run App.new
