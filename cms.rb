require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"
# require 'pry'

configure do
  enable :sessions
  set :session_secret, 'secret'
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

def load_file(path)
  contents = File.read(path)
  case File.extname(path)
  when ".txt"
    headers['Content-Type'] = 'text/plain'
    contents
  when ".md"
    erb render_markdown(contents)
  end
end

def empty_file_name?(file)
  "A name is required" if file.to_s.length <= 0
  end

def existing_filename?(file)
  files = load_file_list
  "#{file} already exists." if files.include?(file.downcase)
end

def invalid_extension?(extension)
  "Document must be either a '.txt' or '.md' file." if
  !VALID_EXTENSIONS.include?(extension)
end

def invalid_characters?(filename)
  "Document name may contain letters, numbers and . _ or - only." if
  filename.match(/[^A-Za-z0-9._-]/) ? true : false
end

def invalid_file?(filename)
  error_message =  empty_file_name?(filename)
    return error_message if error_message
  error_message = existing_filename?(filename)
    return error_message if error_message
  error_message = invalid_extension?(File.extname(filename))
    return error_message if error_message
  error_message = invalid_characters?(filename)
    return error_message if error_message
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

  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

def user_signed_in?
  session.key?(:username)
end

def require_sign_in
  return true if user_signed_in?

  session[:error] = "You must be signed in to do that."
  redirect "/"
end

def empty_username?(username)
  username.length <= 0
end

def existing_username?(username)
  credentials = load_credentials
  credentials.key?(username)
end

def add_new_user(username, password)
  users = load_credentials
  users[username] = password

  output = YAML.dump(users)
  File.write(credentials_path, output)
end


helpers do
  def load_file_list
    pattern = File.join(data_path, "*")
    Dir.glob(pattern).map { |file| File.basename(file) }
  end
end

get "/" do
  load_file_list
  erb :index
end

get "/new" do
  require_sign_in

  erb :new_document
end

post "/new" do
  require_sign_in
  file_name = (params[:filename])

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

  # if empty_file_name?(file_name)
  #   session[:error] = "A name is required"
  #   status 422
  #   erb :new_document
  # elsif existing_filename?(file_name)
  #   session[:error] = "#{file_name} already exists."
  #   status 422
  #   erb :new_document
  # elsif invalid_extension?(File.extname(file_name))
  #   session[:error] = "Document must be either a '.txt' or '.md' file."
  #   status 422
  #   erb :new_document
  # elsif invalid_characters?(params[:filename])
  #   session[:error] = "Document name may contain letters, numbers and . _ or - only."
  #   status 422
  #   erb :new_document
  # else
  #   file_path = File.join(data_path, file_name)
  #   File.write(file_path, "")
  #   session[:success] = "#{params[:filename]} was created."
  #   redirect "/"
  # end
end

get "/:filename" do
  file_path = File.join(data_path, File.basename(params[:filename]))

  if File.exist?(file_path)
    load_file(file_path)
  else
    session[:error] = "#{params[:filename]} does not exist"
    redirect "/"
  end
end

get "/:filename/edit" do
  require_sign_in

  file_path = File.join(data_path, File.basename(params[:filename]))
  @file_name = File.basename(params[:filename])
  @file_contents = File.read(file_path)

  erb :edit
end

post "/:filename" do
  require_sign_in

  file_path = File.join(data_path, File.basename(params[:filename]))
  File.write(file_path, params[:content])

  session[:success] = "#{params[:filename]} has been updated."
  redirect "/"
end

post "/:filename/delete" do
  require_sign_in

  file_path = File.join(data_path, File.basename(params[:filename]))
  File.delete(file_path)

  session[:success] = "#{params[:filename]} has been deleted."
  redirect "/"
end

get "/:filename/copy" do
  require_sign_in

  file_path = File.join(data_path, File.basename(params[:filename]))
  if File.exists?(file_path)
    @file_name = File.basename(params[:filename])
    @file_contents = File.read(file_path)
    
    erb :new_document
  else
    session[:error] = "#{params[:filename]} does not exist"
    redirect "/"
  end
end


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

post "/users/signout" do
  session.delete(:username)

  session[:success] = 'You have been signed out.'
  redirect "/"
end

get "/users/signup" do
  erb :signup
end

post "/users/signup" do
  if empty_username?(params[:username])
    session[:error] = "Username cannot be blank"
    status 422
    erb :signup
  elsif existing_username?(params[:username])
    session[:error] = "Username '#{params[:username]}' already exists."
    status 422
    erb :signup
  else
    bcrypt_password = BCrypt::Password.create(params[:password])
    add_new_user(params[:username], bcrypt_password)

    session[:success] = "Account for #{params[:username]} has been created."
    redirect "/"
  end
end
