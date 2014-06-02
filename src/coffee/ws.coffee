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

define ['utils'], (Utils) ->
  class WS
    constructor: (@ws) ->

    __sendWrapper: (cmd) ->
      Utils.hideNotification()
      @ws.send cmd

    sendKey: (ev, index) ->
      key = String.fromCharCode(ev.which)
      # Only send out alphanumeric char values to prevent other
      # end from breaking because of odd chars
      key = null unless /^[a-zA-Z0-9]+$/.test key
      Utils.log "Send key #{key} (code: #{ev.which}"

      @__sendWrapper JSON.stringify
        type:    Utils.MSG_TYPES.OUT.EVENT
        event:   'keypress'
        frame:   index
        char:    key?.toLowerCase()
        keyCode: ev.which

    sendClick: (ev, index) ->
      x = ev.offsetX
      y = ev.offsetY
      Utils.debug "Send click to #{x},#{y}"

      @__sendWrapper JSON.stringify
        type:  Utils.MSG_TYPES.OUT.EVENT
        event: 'click'
        frame: index
        x: x
        y: y

    reserveHand: ->
      Utils.debug "Reserve hand control"
      @__sendWrapper JSON.stringify
        type: Utils.MSG_TYPES.OUT.LOCK
        lock: true

    releaseHand: ->
      Utils.debug "Release hand control"
      @__sendWrapper JSON.stringify
        type: Utils.MSG_TYPES.OUT.LOCK
        lock: false

    setDevice: (id) ->
      Utils.debug "Select device #{id}"
      @__sendWrapper JSON.stringify
        type:   Utils.MSG_TYPES.OUT.DEVICE
        device: id

    setFindTemplate: (name) =>
      Utils.debug "Set template matching for #{name}"
      name = '' if name == '-- None --'
      @__sendWrapper JSON.stringify
        type:   Utils.MSG_TYPES.OUT.TEMPLATE
        name:   name

    saveReference: (template, name) ->
      Utils.debug "Save reference image"
      @__sendWrapper JSON.stringify
        type:   Utils.MSG_TYPES.OUT.SAVE
        name:   name
        frame:  template.idx
        x1:     template.x1
        y1:     template.y1
        x2:     template.x2
        y2:     template.y2

    startCamera: ->
      @__sendWrapper JSON.stringify
        type:   Utils.MSG_TYPES.OUT.START_CAMERA

    startLiveTemplateMatching: (template) ->
      Utils.debug "Start live matching of selected template area"
      @__sendWrapper JSON.stringify
        type:   Utils.MSG_TYPES.OUT.START_MATCHING
        x1:     template.x1
        y1:     template.y1
        x2:     template.x2
        y2:     template.y2

    stopLiveTemplateMatching: ->
      Utils.debug "Stop live template matching"
      @__sendWrapper JSON.stringify type: Utils.MSG_TYPES.OUT.STOP_MATCHING

    getPosition: ->
      @__sendWrapper JSON.stringify type: Utils.MSG_TYPES.OUT.GET_POSITION

    setPosition: (position) ->
      @__sendWrapper JSON.stringify
        type:     Utils.MSG_TYPES.OUT.SET_POSITION
        position: position

    moveCoord: (axis, distance) ->
      @__sendWrapper JSON.stringify
        type:     Utils.MSG_TYPES.OUT.MOVE_COORD
        axis:     axis
        distance: distance

    resetDeviceCalibration: (device) =>
      @__sendWrapper JSON.stringify
        type:     Utils.MSG_TYPES.OUT.RESET_CALIBRATION
        device:   device
