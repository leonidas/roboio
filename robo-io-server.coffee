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

winston = require 'winston'
path    = require 'path'
fs      = require 'fs'

RoboIO  = require 'src/server/roboio'

SETTINGS_FILE = [__dirname, 'settings.json'].join path.sep

server = null

start_server = (settings_path, cb) ->
  # Reconfigure logger
  winston.remove winston.transports.Console
  winston.add winston.transports.Console,
    timestamp:   true
    colorize:    true
    prettyPrint: true
    level:       if process.env.NODE_ENV == "production" then "verbose" else "verbose" # Set to silly to see even more

  # Check needed environment variables
  if not process.env.PORT? or not process.env.NODE_ENV
    winston.error "PORT and/or NODE_ENV is not defined"
    if cb? then return cb 1 else process.exit 1

  # Read settings file
  settings      = JSON.parse fs.readFileSync settings_path
  settings.root = __dirname

  #server = require('src/server/server').create_app settings
  roboio  = new RoboIO settings
  roboio.start()

stop_server = (cb) ->
  server.close() if server?
  cb?()

# Automatically call only if this is the main function
if !module.parent
  start_server SETTINGS_FILE, (err) ->
    process.exit err if err?
