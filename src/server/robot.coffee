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

thrift  = require 'thrift'
ttr     = require 'node_modules/thrift/lib/thrift/transport'
events  = require 'events'
winston = require 'winston'
_       = require 'lodash'
async   = require 'async'

rata_types  = require 'gen-nodejs/rataservice_types'
rataservice = require 'gen-nodejs/rataservice'

# How often (ms) we try to reconnect to robot? Also used in checking
# for released lock.
RECONN_TIMEOUT = 10000

# How many subsequential errors can the getimage return until we
# call it a day?
MAX_IMAGE_ERRORS = 10

HAND_STATUS =
  LOCKED_FOR_TEST_RUN:  1
  LOCKED_FOR_USER:      2
  LOCKED_FOR_CURR_USER: 3
  FREE:                 4

MESSAGES =
  LOCKED_FOR_TEST_RUN:  'Locked for test execution'
  LOCKED_FOR_USER:      'Locked to '
  LOCKED_FOR_CURR_USER: 'Locked to you'
  FREE:                 'Free'

# Message types coming from clients
CLIENT_MSG_TYPES =
  EVENT:             0   # Keypress, click
  LOCK:              1   # Acquire, release
  DEVICE:            2   # Select device
  TEMPLATE:          4   # Start matching selected template
  SAVE:              5   # Save reference/template
  START_CAMERA:      6   # Start robot camera
  START_MATCHING:    7   # Start live matching when creating a template
  STOP_MATCHING:     8   # Stop live matching (save/cancel create template)
  GET_POSITION:      9   # Get current position of the robot
  SET_POSITION:      10  # Set the position of the robot
  MOVE_COORD:        11  # Move the robot along the selected coordinate
  RESET_CALIBRATION: 12  # Reset the device calibration

# Message types sent to clients
MSG_TYPES =
  STATUS: 0
  STREAM: 1
  POS:    2

#
# Class for handling a single robot
#
module.exports = class Robot

  #
  # Create a new robot. All parameters need to be given.
  #
  constructor: (@conf) ->
    @conf.lock_timeout ||= 5    # Set to 5 minutes if missing from config
    @conf.lock_timeout   = @conf.lock_timeout * 1000 * 60 # To milliseconds

    @connected      = false     # Do we have connection to RATA service?
    @img_connected  = false

    @testrun_on     = false     # Is the robot currently executing tests?
    @streaming      = false     # Are we currently streaming image data to clients?
    @clients        = []        # All clients connected to this robot
    @locked_to      = null      # To whom is this robot controls locked to?
    @locked_to_name = ""
    @lock_timeout   = null      # Handle to the lock timeout
    @devices        = []        # Devices connected to the robot
    @current_device = null      # The device currently selected on the robot
    @disable_ctrls  = false     # True when controls are disabled, e.g. when selecting device
    @templates      = []        # Templates the robot has

    @conn       = null
    @client     = null
    # We use two connections to single server to be able to feed images
    # when performing blocking operations (like clicking).
    @img_conn   = null
    @img_client = null

    # Each robot has it's own event mechanism for controlling clients
    # and image captures
    @ee = new events.EventEmitter()

    # Count errors, and if we get too many errors in a row
    # from getimage stop requesting
    @image_err_counter = 0

    # Message handler method map
    @msg_handlers = {}
    @msg_handlers[CLIENT_MSG_TYPES.EVENT]             = '__handleEventMessage'
    @msg_handlers[CLIENT_MSG_TYPES.LOCK]              = '__handleLockMessage'
    @msg_handlers[CLIENT_MSG_TYPES.DEVICE]            = '__handleSetDeviceMessage'
    @msg_handlers[CLIENT_MSG_TYPES.TEMPLATE]          = '__setFindTemplate'
    @msg_handlers[CLIENT_MSG_TYPES.SAVE]              = '__saveTemplate'
    @msg_handlers[CLIENT_MSG_TYPES.START_CAMERA]      = '__startCamera'
    @msg_handlers[CLIENT_MSG_TYPES.START_MATCHING]    = '__startLiveTemplateMatching'
    @msg_handlers[CLIENT_MSG_TYPES.STOP_MATCHING]     = '__stopLiveTemplateMatching'
    @msg_handlers[CLIENT_MSG_TYPES.GET_POSITION]      = '__getCurrentPosition'
    @msg_handlers[CLIENT_MSG_TYPES.SET_POSITION]      = '__moveToCoordinate'
    @msg_handlers[CLIENT_MSG_TYPES.MOVE_COORD]        = '__moveOnAxis'
    @msg_handlers[CLIENT_MSG_TYPES.RESET_CALIBRATION] = '__resetDeviceCalibration'

  #
  # Open connections to services
  #
  start: ->
    self = @

    self.__setupEvents()
    self.__startService()
    self.__startImageService()

  #
  # Add a client to this robot instance
  #
  addClient: (ws, name) ->
    self = @

    # If robot is currently locked there already is a recursive setTimeout
    # call ongoing that will poll the robot. However if it is not then check
    if !self.testrun_on
      self.__tryLock()

    self.__log 'verbose', "#{name} connected as web client"
    client_obj = {ws: ws, name: name}
    self.clients.push client_obj
    self.ee.emit 'client_connected'
    self.__notifyClientsOfStatusChange ws

    # Note: Even if connects are handled by the RoboIO server,
    # each robot takes care of the client when it leaves
    ws.on 'close', ->
      self.__log 'verbose', "#{name} disconnected"
      self.clients.splice (self.clients.indexOf client_obj), 1
      # Release hand if locked to current client
      if self.locked_to == ws
        self.__releaseLock()

      self.ee.emit 'client_disconnected'

    # Same goes for messages - the will come to the robot instance
    ws.on 'message', (data) ->
      # This function needs to be inline since we need access to both
      # the ws client and the robot
      msg = JSON.parse data
      self.__log 'verbose', "Received a message from web client:", msg

      # Trying to move the robot but either it is not connected, it's
      # currently running tests, or it's not locked to caller
      if msg.type in [CLIENT_MSG_TYPES.EVENT, CLIENT_MSG_TYPES.DEVICE] && (!self.connected || self.testrun_on || this != self.locked_to)
        self.__log 'error', "Command received but not authorized to execute",
          testrun_on:       self.testrun_on
          hand_locked:      self.locked_to?
          locked_to_caller: self.locked_to == ws
        return

      if msg.type == CLIENT_MSG_TYPES.START_CAMERA && self.testrun_on
        self.__log 'error', "Trying to start camera during test execution",
          testrun_on:       self.testrun_on
          hand_locked:      self.locked_to?
          locked_to_caller: self.locked_to == ws
        return

      # Reset unlock timer
      if this == self.locked_to
        self.__resetLockTimeout()

      self[self.msg_handlers[msg.type]] msg, @ if self.msg_handlers[msg.type]?

  #
  # Handle event message coming from web client (click, keypress)
  #
  __handleEventMessage: (msg, client) ->
    self = @

    robotmsg = new rata_types.Event frameId: msg.frame
    switch msg.event
      when 'click'
        robotmsg.type  = rata_types.EventType.MOUSECLICK
        robotmsg.click = new rata_types.MouseClick
          x: msg.x
          y: msg.y

      when 'keypress'
        robotmsg.type     = rata_types.EventType.KEYPRESS
        robotmsg.keypress = new rata_types.KeyPress
          keyCode:   msg.keyCode
          character: msg.char

    # Send command to robot hand if it's connected, locked to caller, and not executing
    if !self.testrun_on && client == self.locked_to
      self.client.handleEvent robotmsg, (err, response) ->
        return self.__log 'error', "Failed to command the robot:", err if err?

        if response.err == rata_types.Error.NONE
          # TODO
          console.log response.message
        # Test run has started at some point between the latest client
        # connecting and client sending a command. We don't poll for the
        # status uselessly, but now that we know it's in use start checking
        # when it's free again
        else if response.err == rata_types.Error.LOCKED
          self.ee.emit 'hand_locked'
          self.__tryLock()
        # Some other error occurred
        else
          self.__log 'error', "Received an error response from the robot", response

  #
  # Handle lock message coming from web client
  #
  __handleLockMessage: (msg, client) ->
    self = @

    # Acquire lock
    if msg.lock
      unless self.testrun_on
        self.locked_to      = client
        self.locked_to_name = _.filter(self.clients, (c) -> c.ws == client)[0].name

        # Start automatic lock release timer
        self.__resetLockTimeout()

        self.ee.emit 'hand_reserved'

    # Release lock
    else
      self.__releaseLock()

  #
  # Handle set device message coming from web client
  #
  __handleSetDeviceMessage: (msg, client) ->
    self = @

    self.__disableControls()

    # Select the device
    self.client.setDevice msg.device, (err, response) ->
      self.__log 'error', "Failed to select device #{msg.device}", err if err? || response != true
      self.disable_ctrls = false
      self.current_device = msg.device if response == true
      # Get templates list and notify regardless of success so that in case of
      # error the callers dropdown will be resetted, and in case of
      # success all other dropdowns get updated
      self.__getTemplates () ->
        self.__notifyClientsOfStatusChange()

  #
  # Events control the status of the robot -- e.g. if last client leaves,
  # this robot instance stops asking for image data
  #
  __setupEvents: ->
    self = @

    self.ee.on 'client_connected', ->
      # Start streaming image data if not yet doing so
      if self.clients.length > 0 && self.img_connected && !self.streaming
        self.streaming = true
        self.__getImage()

    self.ee.on 'client_disconnected', ->
      # Stop streaming if there are no more clients
      if self.clients.length < 1
        self.__log 'info', "Last client left, stop requesting images"
        self.streaming = false

    # Main connection connected (everything else except image streaming)
    self.ee.on 'connected', ->
      self.connected = true

      # When service connects, (re)fetch the templates defined. No point
      # in running these in parallel because the calls block
      self.__getTemplates () ->
        # And get devices as well
        self.__getDevices (err) ->
          # And try the lock
          self.__tryLock (err) ->
            self.__notifyClientsOfStatusChange()

    # Main connection disconnected (everything else except image streaming)
    self.ee.on 'disconnected', ->
      self.disable_ctrls = false
      self.connected     = false
      self.__releaseLock false
      self.__notifyClientsOfStatusChange()

    # Image streaming connection connected
    self.ee.on 'img_connected', ->
      self.img_connected = true
      if self.clients.length > 0
        self.__notifyClientsOfStatusChange()
        self.streaming = true
        self.__getImage()

    # Image streaming connection disconnected
    self.ee.on 'img_disconnected', ->
      self.img_connected = false
      self.streaming     = false
      self.__notifyClientsOfStatusChange()

    self.ee.on 'hand_unlocked', ->
      self.__log 'info', "Robot hand unlocked"
      self.testrun_on = false
      # Update device list after testrun ended, the robot may have
      # used a different device that we think is currently selected
      self.__getDevices (err) ->
        self.__notifyClientsOfStatusChange()

    self.ee.on 'hand_locked', ->
      self.__log 'info', "Robot hand locked"
      self.testrun_on = true
      self.__releaseLock false
      self.__notifyClientsOfStatusChange()

    self.ee.on 'hand_reserved', ->
      self.__log 'info', "Robot hand reserved to user #{self.locked_to_name}"
      self.__notifyClientsOfStatusChange()

    self.ee.on 'hand_released', ->
      self.__log 'info', "Robot hand released by user"
      self.__notifyClientsOfStatusChange()

  #
  # Ask for an image from the robot, and send it to clients if received.
  #
  __getImage: ->
    self = @

    sendImage = (ws, json) -> (cb) -> ws.send json, cb
    toFeed    = (feed) ->
      return {
        index:   feed.content?.id
        png:     feed.content.imagedata
        width:   feed.content?.width
        height:  feed.content?.height
        updated: feed.updated
        message: feed.message
      }

    self.img_client.getvisualfeeds (err, response) ->
      if err?
        self.__log 'error', "Failed to receive image", err
        self.image_err_counter++
      else
        self.image_err_counter = 0

        response = [response] unless _.isArray response

        # Image data is no sent as binary, encode it
        response = _.map response, (feed) ->
          feed.content.imagedata = new Buffer(feed.content?.imagedata, 'binary').toString('base64')
          feed

        data =
          type:         MSG_TYPES.STREAM
          feeds:        (toFeed(feed) for feed in response)
          lock_release: self.__getTimeLeft()

        json     = JSON.stringify(data)
        data     = null
        response = null

        operations = []
        for client in self.clients
          operations.push sendImage client.ws, json

        async.parallel operations, (err) ->
          json = null
          self.__log 'error', "Failed to send image to client:", err if err?

      # Try again even if previous request failed
      self.__getImage() if self.streaming unless self.image_err_counter >= MAX_IMAGE_ERRORS

  #
  # Get device list and current device from robot
  #
  __getDevices: (cb) ->
    self = @

    return cb?() unless self.client.getDevices?

    self.client.getDevices (err, devices) ->
      if err?
        self.__log 'error', "Failed to get device list from robot", err
        cb? err
      else
        self.devices = devices
        # Ask for current device only if we were able to get the device
        self.client.getCurrentDevice (err, device) ->
          if err?
            self.__log 'error', "Failed to get current device", err
            self.current_device = null
            cb? err
          else
            self.current_device = device
            cb?()

  #
  # Get template list
  #
  __getTemplates: (cb) ->
    self = @

    self.client.gettempls (err, templates) ->
      if err?
        self.__log 'error', "Failed to get template list from robot", err
        cb? err
      else
        self.templates = ['-- None --'].concat templates
        cb? null

  #
  # Handle template finding message coming from web client
  #
  __setFindTemplate: (msg) ->
    self = @
    name = msg.name
    name = null if name == ''
    self.client.setfindtempl name, (err, response) ->
      self.__log 'error', "Failed to select device #{msg.device}", err if err? || response != true

  #
  # Handle save template/reference message coming from web client
  #
  __saveTemplate: (msg) ->
    self = @

    # Save template
    if msg.x1?
      topleft     = new rata_types.Coordinate x: msg.x1, y: msg.y1
      bottomright = new rata_types.Coordinate x: msg.x2, y: msg.y2
      self.client.savetempl msg.frame, topleft, bottomright, msg.name, (err, response) ->
        self.__log 'error', "Failed to select device #{msg.device}", err if err? || response != true
        self.__getTemplates () ->
          self.__notifyClientsOfStatusChange()

    # Save reference image
    else
      self.client.savereference msg.frame, msg.name, (err, response) ->
        self.__log 'error', "Failed to select device #{msg.device}", err if err? || response != true

  #
  # Set visual data source to camera
  #
  __startCamera: ->
    self = @
    msg  = new rata_types.VisualSourceRequest()
    msg.source_type = rata_types.VisualSource.CAMTHREAD
    msg.param       = "Wot is dis?"

    self.__log 'verbose', "Starting camera:", msg

    self.client.setVisualDataSource msg, (err, response) ->
      self.__log 'verbose', "Response received", response
      self.__log 'error', "Failed to set visual data source", err if err?

  #
  # Start live matching of template
  #
  __startLiveTemplateMatching: (msg) ->
    self = @
    self.__log 'verbose', "Starting live template matching"

    topleft     = new rata_types.Coordinate x: msg.x1, y: msg.y1
    bottomright = new rata_types.Coordinate x: msg.x2, y: msg.y2
    cmd         = new rata_types.previewmatchingmode enabled: true, topleft: topleft, bottomright: bottomright

    self.client.setpreviewmatchingmode cmd, (err, res) ->
      self.__log 'error', "Failed to set preview matching mode", err if err?

  #
  # Stop live matching of template
  #
  __stopLiveTemplateMatching: ->
    self = @
    self.__log 'verbose', "Stopping live template matching"
    cmd = new rata_types.previewmatchingmode enabled: false
    self.client.setpreviewmatchingmode cmd, (err, res) ->
      self.__log 'error', "Failed to stop preview matching mode", err if err?

  #
  # Get current position of the robot
  #
  __getCurrentPosition: ->
    self = @
    self.__log 'verbose', "Get current position from robot"

    self.__getPositionWrapper (err, res) ->
      self.__enableControls()
      return if err?

      # Send only to the client currently in posession if the lock
      if self.locked_to
        msg =
          type:     MSG_TYPES.POS
          position: res

        self.locked_to.send JSON.stringify(msg), (err) ->
          self.__log 'error', "Failed to send position to client", err if err?

  #
  # Wrapper for getting position. The position is returned as a string due
  # to Thrift bug where nodejs returns floats as zeroes. We will construct
  # an object that looks like RobotCoord
  #
  __getPositionWrapper: (cb) ->
    self = @

    self.client.getposition (err, res) ->
      if err?
        self.__log 'error', "Failed to get position", err
        cb err

      parts = res.replace(/,/g, '.').split ' '
      parts = (parseFloat p for p in parts)
      data  = x: parts[0], y: parts[1], z: parts[2], alfa: parts[3]
      cb null, data

  #
  # Move to given coordinates (x, y, z, alfa)
  #
  __moveToCoordinate: (msg) ->
    self = @
    msg  = msg.position if msg.position?

    self.__disableControls()

    # Convert to RobotCoord
    cmd      = new rata_types.RobotCoord
    cmd[key] = msg[key] for key in _.keys msg
    self.client.setposition cmd, (err, res) ->
      self.__log 'error', "set position!!!"
      if err?
        self.__log 'error', "Failed to move robot", err if err?
        return self.__enableControls()
      self.__getCurrentPosition()

  #
  # Move along given axis
  #
  __moveOnAxis: (msg) ->
    self = @

    self.__disableControls()

    # Get current position
    self.__getPositionWrapper (err, res) ->
      return self.__enableControls() if err?
      res[msg.axis] = res[msg.axis] + msg.distance
      self.__moveToCoordinate res

  #
  # Reset the device calibaration
  #
  __resetDeviceCalibration: (msg) ->
    self = @

    self.__disableControls()
    self.client.reloaddutconfig msg.device.index, (err, res) ->
      self.__log 'error', "Failed to reload config for DUT #{msg.device.index} (#{msg.device.name})", err if err?
      self.__enableControls()

  #
  # Disable controls and inform the one in posession of the lock
  #
  __disableControls: ->
    @disable_ctrls = true
    @__notifyClientsOfStatusChange @locked_to

  #
  # Enable controls and inform the one in posession of the lock
  #
  __enableControls: ->
    @disable_ctrls = false
    @__notifyClientsOfStatusChange @locked_to

  #
  # Check if the robot is locked for test execution
  #
  __tryLock: (cb) ->
    self = @

    if self.connected
      self.client.locked (err, status) ->
        if err?
          self.__log 'error', "Failed to ask if robot is locked. Asking again in #{RECONN_TIMEOUT / 1000} seconds.", err
          setTimeout (() -> self.__tryLock()), RECONN_TIMEOUT
        else
          if self.testrun_on
            # Was locked previosly but is not anymore -> emit
            if !status
              self.ee.emit 'hand_unlocked'
            # Was locked and still is -> try again after some time
            else
              self.__log 'verbose', "Robot is locked. Asking again in #{RECONN_TIMEOUT / 1000} seconds."
              setTimeout (() -> self.__tryLock()), RECONN_TIMEOUT
          else
            # Was not locked previously but is now -> emit and retry
            if status
              self.ee.emit 'hand_locked'
              setTimeout (() -> self.__tryLock()), RECONN_TIMEOUT

      cb?()

  #
  # Start/reset the lock release timer
  #
  __resetLockTimeout: ->
    self = @

    if self.lock_timeout?
      clearTimeout self.lock_timeout
      self.lock_timeout = null

    self.lock_timeout = setTimeout (() ->
      self.__releaseLock()
    ), self.conf.lock_timeout

  #
  # Release the lock from a user
  #
  __releaseLock: (emit = true) ->
    self = @

    self.locked_to      = null
    self.locked_to_name = ""

    clearTimeout self.lock_timeout
    self.lock_timeout = null

    self.ee.emit 'hand_released' if emit

  #
  # How many minutes left until the lock will be released by timer.
  # Returns null if less than 20% of the time has passed, ie. practically
  # full time left
  #
  __getTimeLeft: ->
    self = @
    return null unless self.lock_timeout?
    t = Math.ceil (self.lock_timeout._idleStart +
                   self.lock_timeout._idleTimeout -
                   Date.now())
    return null if t > 0.8 * self.conf.lock_timeout
    return t / 1000 / 60

  #
  # Send hand and eye statuses to all or to given client only
  #
  __notifyClientsOfStatusChange: (client) ->
    self = @

    if self.testrun_on
      hand_status = HAND_STATUS.LOCKED_FOR_TEST_RUN
    else if self.locked_to?
      hand_status = HAND_STATUS.LOCKED_FOR_USER
    else
      hand_status = HAND_STATUS.FREE

    hand_state = MESSAGES[_.invert(HAND_STATUS)[hand_status]]
    if hand_status == HAND_STATUS.LOCKED_FOR_USER
      hand_state = hand_state + self.locked_to_name

    msg =
      type:           MSG_TYPES.STATUS
      eye_status:     self.img_connected
      hand_status:    hand_status
      hand_state:     hand_state
      devices:        self.devices
      current_device: self.current_device
      disable_ctrls:  self.disable_ctrls
      templates:      self.templates

    if client?
      if msg.hand_status == HAND_STATUS.LOCKED_FOR_USER && self.locked_to == client
        msg.hand_status = HAND_STATUS.LOCKED_FOR_CURR_USER
        msg.hand_state  = MESSAGES[_.invert(HAND_STATUS)[msg.hand_status]]

      client.send JSON.stringify(msg), (err) ->
        self.__log 'error', "Failed to send message to client:", err if err?

    else
      for client in self.clients
        # Clone so we can safely change the status based on current client
        sendmsg = _.clone msg

        # Check if hand status is locked for current client
        if sendmsg.hand_status == HAND_STATUS.LOCKED_FOR_USER && self.locked_to == client.ws
          sendmsg.hand_status = HAND_STATUS.LOCKED_FOR_CURR_USER
          sendmsg.hand_state  = MESSAGES[_.invert(HAND_STATUS)[sendmsg.hand_status]]

        client.ws.send JSON.stringify(sendmsg), (err) ->
          self.__log 'error', "Failed to send message to client:", err if err?

  #
  # Open image connection to RATA service
  #
  __startImageService: ->
    return unless @__checkServiceParams @conf.host, @conf.port
    self = @

    self.img_conn   = thrift.createConnection self.conf.host, self.conf.port, transport: ttr.TFramedTransport
    self.img_client = thrift.createClient rataservice, self.img_conn
    connecting      = false

    reconnect = ->
      unless connecting
        connecting    = true
        self.__log    'error', "Connection to RATA image service lost. Reconnecting in #{RECONN_TIMEOUT / 1000} seconds."
        self.ee.emit  'img_disconnected'
        setTimeout (() -> self.__startImageService()), RECONN_TIMEOUT

    self.img_conn.on 'error', reconnect
    self.img_conn.on 'close', reconnect

    self.img_conn.on 'connect', ->
      self.__log   'info', "Connected to RATA image service."
      self.ee.emit 'img_connected'
      self.__stopLiveTemplateMatching()

  #
  # Open connection to RATA service
  #
  __startService: ->
    return unless @__checkServiceParams @conf.host, @conf.port
    self = @

    self.conn      = thrift.createConnection self.conf.host, self.conf.port, transport: ttr.TFramedTransport
    self.client    = thrift.createClient rataservice, self.conn
    connecting     = false

    reconnect = ->
      unless connecting
        connecting    = true
        self.__log    'error', "Connection to RATA service lost. Reconnecting in #{RECONN_TIMEOUT / 1000} seconds."
        self.ee.emit  'disconnected'
        setTimeout (() -> self.__startService()), RECONN_TIMEOUT

    self.conn.on 'error', reconnect
    self.conn.on 'close', reconnect

    self.conn.on 'connect', ->
      self.__log   'info', "Connected to RATA service."
      self.ee.emit 'connected'

  #
  # Check that host and port are given and somewhat valid
  #
  __checkServiceParams: (host, port, service) ->
    if not host? or host == "" or not port? or port == "" or port == 0
      @__log 'error', "Cannot connect to RATA service: host or port missing/incorrect."
      false
    else
      true

  #
  # Logger wrapper to get robot name in each message
  #
  __log: (level, message, cause) ->
    user = if @locked_to? then " User: #{@locked_to_name}: " else ""

    if cause?
      winston.log level, "Robot '#{@conf.name}': #{user}#{message}", cause
    else
      winston.log level, "Robot '#{@conf.name}': #{user}#{message}"
