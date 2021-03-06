#!./node_modules/coffee-script/bin/coffee

# Module dependencies.
require 'coffee-script'
express = require 'express'
util = require 'util'
qs = require 'querystring'
RedisStore = require('connect-redis')(express);
stylus = require 'stylus'
flashify = require 'flashify'

#Create express server
app = module.exports = express()

#Globals
global.site_url = "" # this should probably not be a global variable
global.mongoose = require 'mongoose'
global.redis = require('redis').createClient 6379, '127.0.0.1' #, {'return_buffers' : true})
global.humanize_size = (size) -> # make global so we can use it in the Torrent schema (this is probably a bad way to do this)
  if size < 1024
    return size + ' B'
  size /= 1024
  if size < 1024
    return size.toFixed(0) + ' KiB'
  size /= 1024
  if size < 1024
    return size.toFixed(1) + ' MiB'
  size /= 1024
  if size < 1024
    return size.toFixed(1) + ' GiB'
  size /= 1024
  return size.toFixed(2) + ' TiB'
global.humanize_date = (date) ->
  now = new Date
  deltat = (now - date)/1000 #javascript uses ms

  if deltat < 60
    return "Less than a minute"
  deltat /= 60
  if deltat < 60
    return deltat.toFixed(0) + " minutes"
  deltat /= 60
  if deltat < 24
    return deltat.toFixed(0) + " hours"
  deltat /= 24
  if deltat < 30
    return deltat.toFixed(0) + " days"
  deltat /= 30
  days = Math.floor((deltat % 1)*30)
  if days > 0
    return deltat.toFixed(0) + " months, " + days + " days"
  else
    return deltat.toFixed(0) + " months"

# Configuration
app.configure ->
  app.set 'views', __dirname + '/views'
  app.set 'view engine', 'jade'
  app.use express.bodyParser()
  app.use express.logger()
  app.use express.methodOverride()
  app.use express.cookieParser()
  app.use express.session {secret: 'himitsu', store: new RedisStore}
  app.use flashify
  app.use (req, res, next) ->
    res.locals.query = req.query
    res.locals.username = if req.session.user? then req.session.user.name else undefined
    res.locals.admin = req.session.admin
    res.locals.categories = Categories.categories
    res.locals.meta_categories = Categories.meta_categories
    res.locals.paginate = (page, lastpage) ->
      numlinks = 7
      if lastpage == 1
        return ''

      bound = (i, min, max) ->
        if i < min
          i = min
        else if i > max
          i = max
        i

      if lastpage <= numlinks
         start = 1
         end = lastpage
      else
         start = bound page - (numlinks + 1) >> 1, 1, lastpage - numlinks
         end = start + numlinks

      pagestr = ''

      q = {}
      q[k] = v for k, v of req.query
      make_url = (pagen) ->
        q['page'] = pagen
        req.route.path + '?' + qs.stringify q

      if page != 1
        pagestr += "<a href=\"#{make_url 1}\">&lArr; First</a>"
        pagestr += "<a href=\"#{make_url page - 1}\">&larr; Prev</a>"

      for i in [start..end] by 1
        if i isnt page
          pagestr += "<a href=\"#{make_url i}\">#{i}</a>"
        else
          pagestr += "<span class=\"thispage\">#{i}</span>"

      if page != lastpage
        pagestr += "<a href=\"#{make_url page + 1}\">Next &rarr;</a>"
        pagestr += "<a href=\"#{make_url lastpage}\">Last &rArr;</a>"

      "<div class=\"pagination\">#{pagestr}</div>"
    next()
  app.use app.router
  app.use stylus.middleware {src: __dirname + '/public', compress: true}
  app.use express.static __dirname + '/public'

port = 0
app.configure 'development', ->
  mongoose.connect 'mongodb://localhost/nyaa2'
  app.use express.errorHandler {dumpExceptions: true, showStack: true}
  port = 3000
app.configure 'production', ->
  mongoose.connect 'mongodb://localhost/uguutracker'
  app.use express.errorHandler()
  port = 9000

if process.argv[2]
  global.site_url = process.argv[2]
# Load

torrents = require './controllers/torrents'
users = require './controllers/users'
admin = require './controllers/admin'
Categories = require './models/categories'

# Routes
app.get '/', torrents.list

app.get '/upload', torrents.upload
app.post '/upload', torrents.upload_post

app.get '/torrent/:permalink', torrents.show
app.get '/torrent/:permalink/download', torrents.download
app.get '/torrent/:permalink/delete', torrents.delete
app.post '/torrent/:permalink/edit', torrents.edit
app.get '/categories_json', torrents.categories_json
app.get '/torrent/:permalink/getmarkup', torrents.getmarkup
app.get '/tracker/:infohash', torrents.infohash_exists
app.get '/tracker/:infohash/snatched', torrents.infohash_snatched

app.get '/rss', torrents.rss

app.get '/register', users.register
app.post '/register', users.register_post

app.get '/login', users.login
app.get '/logout', users.logout
app.post '/login', users.login_post

app.get '/user', (req, res) ->
  return res.redirect '/' if !req.session.user?
  req.params.name = req.session.user.name
  users.show req, res
app.get '/user/:name', users.show

isAdmin = (req, res, next) ->
  if req.session.user and req.session.user.admin
    next()
  else
    req.flash 'error', 'Unauthorized.'
    res.redirect '/'

app.get '/admin/users', isAdmin, users.list

app.get '/admin/categories', isAdmin, admin.categories
app.get '/admin/category/:name/edit', isAdmin, admin.category_edit
app.get '/admin/category/new', isAdmin, admin.category_edit
app.post '/admin/category_edit', isAdmin, admin.category_edit_post
app.get '/admin/meta-category/:name/edit', isAdmin, admin.meta_category_edit
app.get '/admin/meta-category/new', isAdmin, admin.meta_category_edit
app.post '/admin/meta-category_edit', isAdmin, admin.meta_category_edit_post
# Listen

app.listen port
console.log "Express server listening on port %d in %s mode", port, app.settings.env
