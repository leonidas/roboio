###
RoboIO, Web UI for test robots
Copyright (c) 2014, Intel Corporation.

This program is free software; you can redistribute it and/or modify it
under the terms and conditions of the GNU Lesser General Public License,
version 2.1, as published by the Free Software Foundation.

This program is distributed in the hope it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for
more details.
###

express = require 'express'
winston = require 'winston'
http    = require 'http'
ws      = require 'ws'
path    = require 'path'
fs      = require 'fs'
flash   = require 'connect-flash'
_       = require 'lodash'
request = require 'request'

mongostore   = require('connect-mongo')(express)
passport     = require 'passport'
LdapStrategy = require('passport-ldapauth').Strategy
LocalStrategy = require('passport-local').Strategy

Robot = require 'src/server/robot'


# Check if user is authenticated already
isAuthenticated = (req, res, next) ->
  return next() if req.isAuthenticated()
  res.redirect '/login'

#
# Server class. Creates a web server, web socket server, and instances
# for controlling each of the robots
#
module.exports = class RoboIO
  constructor: (@settings) ->
    # Express server instance
    @server      = null
    # WebSocket server instance
    @wss         = null

    # Robots controller groups. Group and robot names as keys, robot
    # controller object as value
    @groups      = []
    # Groups and robots for Jade, construct upon initialization
    @routes      = []

    @settings.admins ||= []

    @__createRobots()

  #
  # Start servers and robots
  #
  start: ->
    # Create servers
    @__startExpressServer()
    @__startWebsockServer()

    for group, robots of @groups
      robos = []
      for name, robot of robots
        robot.start()

  #
  # Instantiate each robot but do not start them yet
  #
  __createRobots: ->
    self = @
    for group, robots of self.settings.groups
      self.groups[group] ||= {}
      robos = []
      for robot in robots
        robos.push robot.name
        robot.lock_timeout = self.settings.lock_timeout
        self.groups[group][robot.name] = new Robot robot
      self.routes.push group: group, robots: robos

  #
  # Start the Express, i.e. web, server that serves HTML/JS/CSS/images
  #
  __startExpressServer: ->
    self = @

    # Pipe Express log to Winston
    winston_stream =
      write: (str) -> winston.verbose str

    if self.settings.authmethod is 'ldapauth'
      self.__initLdapAuth()
    else
      self.__initLocalAuth()

    app = express()

    self.store        = new mongostore db: "roboio-sessions-#{process.env.NODE_ENV}"
    self.cookieParser = express.cookieParser('robots love cookies')

    app.configure ->
      app.use express.static [self.settings.root, 'public'].join path.sep

      app.use self.cookieParser
      app.use express.bodyParser()
      app.use express.session
        key:    'roboio.sid'
        secret: 'robots love cookies'
        store:  self.store
      app.use flash()
      app.use passport.initialize()
      app.use passport.session()

    app.configure 'development', ->
      app.use express.logger stream: winston_stream
      app.use express.errorHandler
        dumpExceptions: true
        showStack:      true

    app.configure 'production', ->
      app.use express.logger stream: winston_stream
      app.use express.errorHandler()

    app.set 'view engine', 'jade'
    app.set 'views', [self.settings.root, 'src', 'jade'].join path.sep
    app.set 'view options', layout: false

    self.__initLogin app

    self.__initJenkinsApi app

    app.get "/:group?/:robot?", isAuthenticated, (req, res) ->
      # Group missing or invalid
      if not req.params.group? || not self.groups.hasOwnProperty req.params.group
        group = Object.keys(self.groups)[0]
        robot = Object.keys(self.groups[group])[0]
        return res.redirect "/#{group}/#{robot}"

      group = req.params.group

      # Robot missing or invalid
      if not req.params.robot? || not self.groups[group].hasOwnProperty req.params.robot
        robot = Object.keys(self.groups[group])[0]
        return res.redirect "/#{group}/#{robot}"

      robot = req.params.robot
      robo_settings = _(self.settings.groups[group])
        .filter((r) -> r.name == robot)
        .map((r) -> r.jenkins.params)
        .valueOf()[0]

      res.render 'index.jade',
        groups:  self.routes
        current: {group: group, name: robot}
        user:    req.user?.name
        admin:   req.user?.admin
        duts:    JSON.stringify self.settings.duts
        robo:    JSON.stringify robo_settings

    # If not matching any real route, redirect.
    app.get "*", isAuthenticated, (req, res) ->
      group = Object.keys(self.groups)[0]
      robot = Object.keys(self.groups[group])[0]
      return res.redirect "/#{group}/#{robot}"

    @server = http.createServer app
    @server.listen process.env.PORT,
      if process.env.NODE_ENV == 'production' then 'localhost' else null

    winston.info "Server listing on port #{process.env.PORT}"

  # Set login/logout routes and handlers
  __initLogin: (app) ->
    self = @

    app.get '/logout', (req, res) ->
      req.flash 'error', 'Logged out!'
      req.logout()
      res.redirect '/'

    app.get '/login', (req, res) ->
      res.render 'login.jade',
        groups: {}
        errmsg: req.flash 'error' if req.flash?
        user:   null
        askpasswd: self.settings.authmethod is 'ldapauth'

    app.post '/login', passport.authenticate(self.settings.authmethod, failureRedirect: '/login', failureFlash: true), (req, res) ->
      res.redirect '/'

  # Initialize the Jenkins API
  __initJenkinsApi: (app) ->
    self = @
    # This API needs two parameters, rest are passed on to Jenkins. The
    # required params are group and robot by which we can locate the correct
    # item from settings and thus get the correct Jenkins job URL
    app.post '/jenkins/start', isAuthenticated, (req, res) ->
      return res.send 400 unless req.body.group? && req.body.robot?
      return res.send 400 unless self.settings.groups[req.body.group]?
      robot = _.filter self.settings.groups[req.body.group], (g) -> g.name == req.body.robot
      return res.send 400 unless robot?[0]?

      params = req.body
      # Remove unneeded params
      delete params.group
      delete params.robot
      # Add token and user email address
      params.token         = robot[0].jenkins.token
      params.EMAIL_ADDRESS = req.user.email

      # Initiate a test run
      request.post "#{robot[0].jenkins.job}/build", form: params, (err, response, body) ->
        if err?
          winston.error "Jenkins launch failed: ", err
          winston.error "Params:", params
          return res.send 400, {type: 'http', jobUri: robot[0].jenkins.job}
        # Jenkins does not return information to track queued build.
        # It gives 302 with a Location header, i.e. redirecting to
        # the queue, see https://issues.jenkins-ci.org/browse/JENKINS-12827).
        # So if we got a 302 send out 200, otherwise send what we got.
        rst = if response.statusCode == 302 then 200 else response.statusCode
        res.send rst, {type: 'jenkins', jobUri: robot[0].jenkins.job}

  # Initialize Passport authentication against LDAP server
  __initLdapAuth: ->
    self = @

    # Convert the CA cert to a buffer in an array
    if @settings.ldap.tlsOptions? && @settings.ldap.tlsOptions.ca?
      @settings.ldap.tlsOptions.ca = [
        fs.readFileSync path.join @settings.root, @settings.ldap.tlsOptions.ca
      ]

    passport.serializeUser (user, cb) ->
      is_admin  = _.indexOf(self.settings.admins, user.mail) > -1
      cb null, {name: user.displayName, email: user.mail, admin: is_admin}

    passport.deserializeUser (user, cb) ->
      cb null, user

    passport.use new LdapStrategy server: @settings.ldap

  # NOTICE: dummy method to bypass problem in connecting to LDAP server:
  # the user is not actually authenticated. Can be extended later to use, e.g,
  # a user database.
  __initLocalAuth: ->
    self = @

    passport.serializeUser (user, cb) ->
      is_admin  = _.indexOf(self.settings.admins, user) > -1
      cb null, {name: user, email: user, admin: is_admin}

    passport.deserializeUser (user, cb) ->
      cb null, user

    passport.use new LocalStrategy (username, password, cb) ->
      cb null, username

  # The WebSocket server is used for communication between
  # the web client (i.e. browser) and this service. It listens
  # to messages from the browser, and sends new images to it
  __startWebsockServer: ->
    self = @

    self.wss = new ws.Server {server: self.server}

    # Web client connects
    self.wss.on 'connection', (ws) ->
      # Store the clients so we can send them new data
      winston.verbose "Web client connected"
      params = _.compact ws.upgradeReq.url.split('/')
      return ws.close() unless params.length == 2
      return ws.close() unless self.groups.hasOwnProperty params[0]
      return ws.close() unless self.groups[params[0]].hasOwnProperty params[1]

      # Parse the cookie from Express
      self.cookieParser ws.upgradeReq, null, (err) ->
        if err?
          winston.error 'Failed to parse cookie', err
          return ws.close()
        sid = ws.upgradeReq.signedCookies['roboio.sid']
        # Locate the session from our session store
        self.store.get sid, (err, session) ->
          if err?
            winston.error 'Failed to get session', err
            return ws.close()

          # Add the client to correct robot
          self.groups[params[0]][params[1]].addClient ws, session.passport.user.name

    winston.info "WebSocket server started and accepting client connections"
