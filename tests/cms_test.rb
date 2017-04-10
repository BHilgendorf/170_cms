ENV["RACK_ENV"] = "test"

require "fileutils"

require "minitest/autorun"
require "rack/test"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)  #data_path method available since defined in global scope 
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def test_index
    create_document("about.md")
    create_document("changes.txt")

    get "/"

    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "about.md")
    assert_includes(last_response.body, "changes.txt")

  end

  def test_view_text_file
    # skip
    create_document("history.txt", "2001: 20th Anniversary")
    get "/history.txt"

    assert_equal(200, last_response.status)
    assert_equal("text/plain", last_response['Content-Type'])
    assert_includes(last_response.body, "2001: 20th Anniversary")
  end

  def test_view_markdown_file
    # skip
    create_document("about.md", "<strong>Bold Text</strong><h2>Header</h2>")
    get "/about.md"

    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "<strong>Bold Text</strong>")
    assert_includes(last_response.body, "<h2>Header</h2>")
  end

  def test_file_not_found_redirect
    # skip
    get "/nofile.txt"
    assert_equal(302, last_response.status)

    get last_response["Location"]
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "nofile.txt does not exist")
  end

  def test_edit_page
    # skip
    create_document("changes.txt")
    get "/changes.txt/edit"

    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<textarea")
    assert_includes(last_response.body, %q(<button type="submit"))
  end

  def test_submit_edit_page
    # skip
    post "/changes.txt", content: "edited content"
    assert_equal(302, last_response.status)

    get last_response["Location"]
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "changes.txt has been updated.")

    get "/changes.txt"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "edited content")
  end

  def test_get_new_document_page
    get "/new"

    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<input")
    assert_includes(last_response.body, %q(<button type="submit"))
  end

  def test_create_new_document_with_blank_name
    post "/new", filename: ""

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "A name is required")
  end

  def test_create_new_document_with_no_extension
    post "/new", filename: "test"

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "Document must be either a '.txt' or '.md' file.")
  end

  def test_create_new_document_with_invalid_extension

    post "/new", filename: "test.pdf"

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "Document must be either a '.txt' or '.md' file.")
  end

  def test_create_new_document_with_valid_name
    post "/new", filename: "test.txt"
    assert_equal(302, last_response.status)

    get last_response["Location"]
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "test.txt was created.")

    get "/"
    assert_includes(last_response.body, "test.txt")
  end
end