require 'sinatra'
require 'sinatra/config_file'
require 'haml'
require 'sinatra/reloader' if settings.development?
require 'pry' if settings.development? || settings.test?

# configuration
configure do
  set :app_root, File.expand_path('../', __FILE__)
  set :reserved, ['login', 'logout', 'upload']
end
if File.exists? "#{settings.app_root}/config.yml"
  config_file "#{settings.app_root}/config.yml"
else
  raise "dude, where's my config.yml?" if settings.production?
  config_file "#{settings.app_root}/config.yml.example"
end
set :sessions, key: settings.session_name, secret: settings.session_secret

# helpers
helpers do
  def logged_in?
    auth ||=  Rack::Auth::Basic::Request.new(request.env)
    if auth.provided? && auth.basic? && auth.credentials
      auth.credentials == [settings.username, settings.password]
    else
      session[:username] == settings.username
    end
  end
  def all_shorts
    all = {}
    Dir.glob("#{settings.app_root}/public/uploads/*.short.*").each do |f|
      name = File.basename(f).split('.short.').first
      all[name] = {
        src:   'uploads/' + File.basename(f),
        type:  'img', #TODO
        name:  name,
        time:  File.mtime(f).to_s,
        title: nil,
      }
    end
    all
  end
  def mk_rand
    chars = [('a'..'z'), ('A'..'Z'), ('0'..'9')].map { |i| i.to_a }.flatten
    (0...settings.random_length).map { chars[rand(chars.length)] }.join
  end
  def get_shorter
    short = mk_rand
    tries = 0
    while all_shorts.include?(short) || settings.reserved.include?(short)
      short = mk_rand
      tries += 1
      raise "this isn't random enough" if tries > settings.random_retries
    end
    short
  end
end

# authentication
post '/login' do
  pass if logged_in?
  uname = params[:username] || ''
  pword = params[:password] || ''
  if uname.empty? || pword.empty?
    status 400
    haml :login, locals: {error_msg: 'You must fill out all fields'}
  elsif uname != settings.username || pword != settings.password
    status 401
    haml :login, locals: {error_msg: 'Invalid username/password'}
  else
    session[:username] = uname
    redirect '/'
  end
end
get '/logout' do
  pass unless logged_in?
  session.delete(:username)
  redirect '/'
end

# uploading
get '/upload' do
  pass unless logged_in?
  haml :upload
end
post '/upload' do
  pass unless logged_in?
  if params[:file].nil? || params[:file].empty?
    status 400
    haml :upload, locals: {error_msg: 'You must supply a valid file'}
  else
    short = get_shorter
    sname = short + '.short' + File.extname(params['file'][:filename])
    File.open("#{settings.app_root}/public/uploads/#{sname}", 'w') do |f|
      f.write(params['file'][:tempfile].read)
    end
    headers 'X-Short' => short
    redirect "/#{short}"
  end
end

# le getshort routes
get '/' do
  if logged_in?
    headers 'X-Upshort-Auth' => 'true'
    sorted = all_shorts.values.sort_by {|h| h[:time]}.reverse
    haml :index, locals: {shorts: sorted}
  else
    headers 'X-Upshort-Auth' => 'false'
    haml :login
  end
end
get '/:short' do |short|
  pass unless all_shorts.include?(short)
  haml :show, locals: {short: all_shorts[short]}
end
delete '/:short' do |short|
  pass unless logged_in? && all_shorts.include?(short)
  Dir.glob("#{settings.app_root}/public/uploads/#{short}.*").each do |f|
    File.delete(f)
  end
  status 204
end
