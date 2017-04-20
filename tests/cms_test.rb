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
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => {username: "admin" } }
  end

  def delete_test_user(username)
    credentials = load_credentials
    credentials.delete(username)
    File.open(credentials_path, 'w') { |f| YAML.dump(credentials, f)}
  end

  def test_index_page
    create_document("about.md")
    create_document("changes.txt")

    get "/"
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "about.md")
    assert_includes(last_response.body, "changes.txt")

  end

  def test_view_text_file
    create_document("history.txt", "2001: 20th Anniversary")
    get "/history.txt"

    assert_equal(200, last_response.status)
    assert_equal("text/plain", last_response['Content-Type'])
    assert_includes(last_response.body, "2001: 20th Anniversary")
  end

  def test_view_markdown_file
    create_document("about.md", "<strong>Bold Text</strong><h2>Header</h2>")
    get "/about.md"

    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "<strong>Bold Text</strong>")
    assert_includes(last_response.body, "<h2>Header</h2>")
  end

  def test_file_not_found_redirect
    get "/nofile.txt"
    assert_equal(302, last_response.status)

    assert_equal("nofile.txt does not exist", session[:error])
  end

  def test_edit_page
    create_document("changes.txt")
    get "/changes.txt/edit", {}, admin_session

    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<textarea")
    assert_includes(last_response.body, %q(<button type="submit"))
  end

  def test_submit_edit_page
    post "/changes.txt", {content: "edited content"}, admin_session

    assert_equal(302, last_response.status)

    assert_equal("changes.txt has been updated.", session[:success])

    get "/changes.txt"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "edited content")
  end

  def test_get_new_document_page
    get "/new", {}, admin_session

    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<input")
    assert_includes(last_response.body, %q(<button type="submit"))
  end

  def test_create_new_document_with_blank_filename
    post "/new", {filename: ""}, admin_session

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "A name is required")
  end

  def test_create_new_document_with_invalid_characters
    post "/new", {filename: "t3&t/test.txt"}, admin_session

    assert_equal(422, last_response.status)
    message = "Document name may contain letters, numbers and . _ or - only."
    assert_includes(last_response.body, message)
  end

  def test_create_new_document_with_existing_filename
    post "/new", {filename: "test.txt"}, admin_session
    post "/new", {filename: "test.txt"}, admin_session

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "test.txt already exists.")
  end

  def test_create_new_document_with_valid_name
    post "/new", {filename: "test.txt"}, admin_session
    assert_equal(302, last_response.status)

    assert_equal("test.txt was created.", session[:success])

    get "/"
    assert_includes(last_response.body, "test.txt")
  end

  def test_create_new_document_with_no_extension
    post "/new", {filename: "test"}, admin_session

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "Document must be either a '.txt' or '.md' file.")
  end

  def test_create_new_document_with_invalid_extension
    post "/new", {filename: "test.pdf"}, admin_session

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "Document must be either a '.txt' or '.md' file.")
  end

  def test_delete_document
    create_document("test.txt")

    post "/test.txt/delete", {}, admin_session
    assert_equal(302, last_response.status)

    assert_equal("test.txt has been deleted.", session[:success])

    get "/"
    refute_includes(last_response.body, %q(href="/test.txt"))
  end

  def test_signin_page
    get "/users/signin"

    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<input")
    assert_includes(last_response.body, %q(<button type="submit"))
  end

  def test_signin_valid_credentials
    post "/users/signin", username: "admin", password: "secret"

    assert_equal(302, last_response.status)
    assert_equal("Welcome!", session[:success])
    assert_equal("admin", session[:username])
  end

  def test_signin_invalid_credentials
    post "/users/signin", username: "John", password: "password"

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "Invalid Credentials")
    assert_nil(session[:username])
  end

  def test_signout
    get "/", {}, {"rack.session" => {username: "admin"} }
    assert_includes(last_response.body, "Signed in as admin")

    post "/users/signout"
    get last_response["Location"]

    assert_nil(session[:username])
    assert_includes(last_response.body, "You have been signed out.")
    assert_includes(last_response.body, "Sign In")
  end

  def test_signed_out_user_cannot_visit_edit_page
    create_document("test.txt")
    get "/test.txt/edit"

    assert_equal("You must be signed in to do that.", session[:error])
    assert_equal(302, last_response.status)
  end

  def test_signed_out_user_cannot_submit_edit_file
    post "/changes.txt"

    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:error])
  end

  def test_signed_out_user_cannot_view_new_document_page
    get "/new"

    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:error])
  end

  def test_signed_out_user_cannot_submit_new_document
    post "/new", filename: "test.txt"

    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:error])
  end

  def test_signed_out_user_cannot_delete_file
    create_document("test.txt")

    post "/test.txt/delete"
    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:error])
  end

  def test_singup_page
    get "/users/signup"

    assert_equal(200, last_response.status)
    assert_includes(last_response.body, %q(<button type="submit"))
  end

  def test_signup_empty_username
    post "/users/signup", username: "", password: "password"

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "Username cannot be blank")
    assert_nil(session[:username])
  end

  def test_signup_existing_username
    post "/users/signup", username: "admin", password: "password"

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "Username 'admin' already exists.")
    assert_nil(session[:username])
  end

  def test_signup_successful
    delete_test_user("testuser")
    post "/users/signup", username: "testuser", password: "testing"

    assert_equal(302, last_response.status)
    assert_equal("Account for testuser has been created.", session[:success])

    get last_response["Location"]
    assert_equal(200, last_response.status)
  end

  def test_added_user_signin
    delete_test_user("testuser")
    post "/users/signup", username: "testuser", password: "testing"

    post "/users/signin", username: "testuser", password: "testing"

    assert_equal(302, last_response.status)
    assert_equal("Welcome!", session[:success])
    assert_equal("testuser", session[:username])
  end
end