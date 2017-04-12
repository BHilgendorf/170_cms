require 'sinatra'
require 'sinatra/reloader'
require "tilt/erubis"
require "redcarpet"
# require 'pry'


configure do
  enable :sessions
  set :session_secret, 'secret'
end

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

def empty_name?(file)
  file.to_s.length <= 0 
end

def invalid_extension?(ext)
  !(ext == ".txt" || ext == ".md")
end

def user_signed_in?
  session.has_key?("username")
end

helpers do
  def user_name
    params[:username] || ""
  end
end

get "/" do
  pattern = File.join(data_path, "*")

  @docs = Dir.glob(pattern)
  @docs.map! { |file| File.basename(file)}

  erb :index
end

get "/new" do

  erb :new_document
end

post "/new" do
  if empty_name?(params[:filename])
    session[:message] = "A name is required"
    status 422
    erb :new_document
  elsif invalid_extension?(File.extname(params[:filename]))
    session[:message] = "Document must be either a '.txt' or '.md' file."
    status 422
    erb :new_document
  else
    file_path = File.join(data_path, params[:filename])
    File.write(file_path, "")

    session[:message] = "#{params[:filename]} was created."
    redirect "/"
  end
end

get "/:filename" do
  file_path = File.join(data_path, params[:filename])

  if File.exists?(file_path)
    load_file(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist"
    status 422
    redirect "/"
  end
end

get "/:filename/edit" do

  if user_signed_in?
    file_path = File.join(data_path, params[:filename])
    @file_name = params[:filename]
    @file_contents = File.read(file_path)

    erb :edit
  else
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

post "/:filename" do
  file_path = File.join(data_path, params[:filename])
  File.write(file_path, params[:content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

post "/:filename/delete" do
  file_path = File.join(data_path, params[:filename])
  File.delete(file_path)

  session[:message] = "#{params[:filename]} has been deleted."
  redirect "/"
end

get "/users/signin" do

  erb :signin
end

post "/users/signin" do
  if params[:username] == 'admin' && params[:password] == 'secret'
    session[:message] = 'Welcome!'
    session[:username] = "#{params[:username]}"
    redirect "/"
  else
    session[:message] = 'Invalid Credentials'
    status 422
    erb :signin
   end
end

post "/users/signout" do
  session.delete(:username)

  session[:message] = 'You have been signed out.'
  redirect "/"
end


