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

should  = require('chai').Should()
mockery = require 'mockery'

events = require 'events'
util   = require 'util'

describe 'Robot', ->

  # WebSocket "client"
  Socket = ->
    events.EventEmitter.call this
    this.send = (msg, cb) ->
      cb? null
    this.disconnect = ->
      this.emit 'close'

    this

  util.inherits Socket, events.EventEmitter

  robot   = null
  ws_mock = null

  before (cb) ->
    mockery.enable()

    thriftClient =
      request: (req, cb) ->
        cb? null
      locked: (req, cb) ->
        cb? null, false
      gettempls: (cb) ->
        cb? null, ['template 1', 'template 2']
      getDevices: (cb) ->
        cb? null, [
          id: 123
          name: 'Dev 1'
        ,
          id: 3425
          name: 'Dev 2'
        ]
      getCurrentDevice: (cb) ->
        cb? null,
          id: 123
          name: 'Dev 1'

    thrift_mock =
      createConnection: (host, port, transport) ->
        this
      createClient: (service, conn) ->
        thriftClient
      on: (ev, cb) ->
        cb?() if ev == 'connect'

    mockery.registerMock 'thrift', thrift_mock

    ws_mock = new Socket()

    # Don't warn about unregistered, otherwise would have to list tens of modules as allowed
    mockery.warnOnUnregistered false
    cb?()

  beforeEach (cb) ->
    Robot = require 'src/server/robot'
    robot = new Robot
      name: 'TestRobot'
      host: 'eyehost'
      port: 22222
    robot.start()
    cb?()

  it 'should start capturing when a client connects', (cb) ->
    robot.clients.length.should.equal 0 # Check we currently have no clients
    robot.streaming.should.be.false     # And that we are not streaming
    robot.addClient ws_mock             # Then add the mock client
    robot.streaming.should.be.true      # Now streaming should be on
    robot.streaming = false             # Stop the streaming

    cb?()

  it 'should stop capturing images when last client leaves', (cb) ->
    robot.addClient ws_mock
    robot.clients.length.should.equal 1
    robot.streaming.should.be.true

    ws_mock.disconnect()
    robot.streaming.should.be.false

    cb?()

  it 'should send the status of services to client when client joins', (cb) ->
    first_msg = null
    ws = new Socket()
    ws.send = (msg, cb) ->
      first_msg = JSON.parse(msg) unless first_msg?
      cb? null

    robot.addClient ws
    first_msg.eye_status.should.be.true
    first_msg.hand_status.should.equal 4
    first_msg.eye_status.should.be.true
    first_msg.hand_state.should.equal 'Free'
    cb?()

  after (cb) ->
    mockery.disable()
    mockery.deregisterAll()
    cb?()
