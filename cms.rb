require 'sinatra'
require 'sinatra/reloader'
require "tilt/erubis"
require "redcarpet"
# require "pry"


root = File.expand_path("..", __FILE__)

configure do
  enable :sessions
  set :session_secret, 'secret'
end

def render_markdown(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(text)
end

def load_file(path)
    contents = File.read(path)
    case File.extname(path)
    when ".txt"
      headers['Content-Type'] = 'text/plain'
      contents
    when ".md"
      render_markdown(contents)
    end
end

get "/" do
  @docs = Dir.glob(root + "/data/*")
  @docs.map! { |file| File.basename(file)}

  erb :index
end

get "/:filename" do
  file_path = root + "/data/" + params[:filename]

  if File.exists?(file_path)
    load_file(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist"
    redirect "/"
  end
end

get "/:filename/edit" do
  file_path = root + "/data/" + params[:filename]
  @file_name = params[:filename]
  @file_contents = File.read(file_path)

  erb :edit
end

post "/:filename" do
  file_path = root + "/data/" + params[:filename]
  File.write(file_path, params[:content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end
