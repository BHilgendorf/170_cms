ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_index
    get "/"

    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "about.md")
    assert_includes(last_response.body, "history.txt")
    assert_includes(last_response.body, "changes.txt")

  end

  def test_display_file
    get "/history.txt"

    assert_equal(200, last_response.status)
    assert_equal("text/plain", last_response['Content-Type'])
    assert_includes(last_response.body, "2001: 20th Anniversary")
  end

  def test_file_not_found_redirect
    get "/nofile.txt"
    assert_equal(302, last_response.status)

    get last_response["Location"]
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "nofile.txt does not exist")
  end

  def test_view_markdown_file
    get "/about.md"

    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "<h2>Moots Cycles</h2>")
    assert_includes(last_response.body, "<strong>handcrafting</strong>")
  end

  def test_edit_page
    get "/changes.txt/edit"

    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<textarea")
    assert_includes(last_response.body, %q(<button type="submit"))
  end

  def test_submit_edit_page
    post "/changes.txt", content: "edited content"
    assert_equal(302, last_response.status)

    get last_response["Location"]
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "changes.txt has been updated.")

    get "/changes.txt"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "edited content")
  end
end