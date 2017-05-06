require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"
require "sanitize"
# require 'pry'

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, escape_html: true
end

VALID_EXTENSIONS = ['.md', '.txt']

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../tests/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def load_file_path
  File.join(data_path, File.basename(params[:filename]))
end

def load_file(path)
  contents = File.read(path)
  case File.extname(path)
  when ".txt"
    headers['Content-Type'] = 'text/plain'
    contents
  when ".md"
    render_markdown(Sanitize.fragment(contents, Sanitize::Config::RELAXED))
  end
end

def empty_file_name?(file)
  file.to_s.length <= 0
end

def existing_filename?(file)
  files = load_file_list
  files.include?(file.downcase)
end

def invalid_extension?(extension)
  !VALID_EXTENSIONS.include?(extension)
end

def invalid_characters?(filename)
  filename.match(/[^A-Za-z0-9_]/)
end

def invalid_file?(filename)
  if empty_file_name?(filename)
    "A name is required"
  elsif existing_filename?(filename)
    "#{filename} already exists."
  elsif invalid_extension?(File.extname(filename))
    "Document must be either a '.txt' or '.md' file."
  elsif invalid_characters?(filename)
    "Document name may contain letters, numbers and/or underscore only."
  end
end

def credentials_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../tests/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
end

def load_credentials
  YAML.load_file(credentials_path)
end

def valid_credentials?(username, password)
  credentials = load_credentials

  return unless credentials.key?(username)
  bcrypt_password = BCrypt::Password.new(credentials[username])
  bcrypt_password == password
end

def user_signed_in?
  session.key?(:username)
end

def empty_username?(username)
  username.length <= 0
end

def existing_username?(username)
  credentials = load_credentials
  credentials.key?(username)
end

def invalid_user_signup?(username)
  if empty_username?(username)
    "Username cannot be blank"
  elsif existing_username?(username)
    "Username '#{username}' already exists."
  elsif invalid_characters?(username)
    "Username may contain letters, numbers and/or underscore only."
  end
end

def add_new_user(username, password)
  users = load_credentials
  users[username] = password

  output = YAML.dump(users)
  File.write(credentials_path, output)
end

def require_sign_in
  return if user_signed_in?

  session[:error] = "You must be signed in to do that."
  redirect "/"
end

helpers do
  def load_file_list
    pattern = File.join(data_path, "*")
    Dir.glob(pattern).map { |file| File.basename(file) }
  end
end

# Get Index Page -----------------------
get "/" do
  load_file_list
  erb :index
end

#  New Document -----------------------
get "/new" do
  require_sign_in
  erb :new_document
end

post "/new" do
  require_sign_in
  file_name = params[:filename]

  error_message = invalid_file?(file_name)
  if error_message
    status 422
    session[:error] = error_message
    erb :new_document
  else
    file_path = File.join(data_path, file_name)
    File.write(file_path, params[:content] || "")
    session[:success] = "#{params[:filename]} was created."
    redirect "/"
  end
end

# Display Existing File -------------------------
get "/:filename" do
  file_path = load_file_path

  if File.exist?(file_path)
    load_file(file_path)
  else
    session[:error] = "#{params[:filename]} does not exist"
    redirect "/"
  end
end

# Edit Existing File -----------------------------
get "/:filename/edit" do
  require_sign_in

  file_path = load_file_path
  @file_name = File.basename(params[:filename])
  @file_contents = File.read(file_path)

  erb :edit
end

post "/:filename" do
  require_sign_in

  file_path = load_file_path
  File.write(file_path, params[:content])

  session[:success] = "#{params[:filename]} has been updated."
  redirect "/"
end

# Delete Existing File ----------------------------------
post "/:filename/delete" do
  require_sign_in

  file_path = load_file_path
  File.delete(file_path)

  session[:success] = "#{params[:filename]} has been deleted."
  redirect "/"
end

# Copy Existing File ------------------------------------
get "/:filename/copy" do
  require_sign_in

  file_path = load_file_path
  if File.exist?(file_path)
    @file_name = File.basename(params[:filename])
    @file_contents = File.read(file_path)

    erb :new_document
  else
    session[:error] = "#{params[:filename]} does not exist"
    redirect "/"
  end
end

# Existing User Sign in -------------------------------------------
get "/users/signin" do
  erb :signin
end

post "/users/signin" do
  username = params[:username]
  if valid_credentials?(username, params[:password])
    session[:success] = 'Welcome!'
    session[:username] = username
    redirect "/"
  else
    session[:error] = 'Invalid Credentials'
    status 422
    erb :signin
  end
end

# Existing User Sign Out -----------------------
post "/users/signout" do
  session.delete(:username)

  session[:success] = 'You have been signed out.'
  redirect "/"
end

# New User Signup -------------------------------
get "/users/signup" do
  erb :signup
end

post "/users/signup" do
  error_message = invalid_user_signup?(params[:username])
  if error_message
    status 422
    session[:error] = error_message
    erb :signup
  else
    bcrypt_password = BCrypt::Password.create(params[:password])
    add_new_user(params[:username], bcrypt_password)

    session[:success] = "Account for #{params[:username]} has been created."
    redirect "/users/signin"
  end
end
