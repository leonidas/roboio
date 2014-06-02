/*
 * RoboIO, Web UI for test robots
 * Copyright (c) 2014, Intel Corporation.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU Lesser General Public License,
 * version 2.1, as published by the Free Software Foundation.
 *
 * This program is distributed in the hope it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for
 * more details.
 */

struct Coordinate {
    1: i16 x,
    2: i16 y
}

struct Point {
    1: double x,
    2: double y
}

enum VisualSource {
    CAMTHREAD, IMAGE
}

struct VisualSourceRequest {
    1: VisualSource source_type,
    2: string param
}

struct RobotCoord {
    1: double x,
    2: double y,
    3: double z,
    4: double alfa
}

/**
 Image struct is used to serve base64 encoded png image
 to webclient which can provide visual run-time monitoring
 */
struct Image {
    1: i32 id,
    2: binary imagedata,
    3: i16 height,
    4: i16 width
}

enum EventType {
  KEYPRESS   = 1,
  MOUSECLICK = 2
}

enum Error {
  NONE = 0,
  LOCKED = 1,
  OTHER = 2
}

struct KeyPress {
  1: i16    keyCode,
  2: string character
}

struct MouseClick {
  1: i16 x,
  2: i16 y
}

struct Event {
  1: i32        frameId,
  2: EventType  type,
  3: KeyPress   keypress,
  4: MouseClick click
}

struct Response {
  1: Error  err,
  2: string message
}

struct previewmatchingmode {
    1: bool enabled,
    2: Coordinate topleft,
    3: Coordinate bottomright
}

struct visualfeed {
    1: Image content,
    2: bool updated,
    3: string message
}

service rataservice {
    /**
    * getvisualfeeds returns feeds which can be visualized for users
    */
    list<visualfeed> getvisualfeeds(),

    /**
    * sets matching preview mode and visual feed for matching
    */
    bool setpreviewmatchingmode(1: previewmatchingmode modesettings),

    /**
    * Reset visual data source
    */
    bool setVisualDataSource(1: VisualSourceRequest req),

    /**
    * Get list of devices
    */
    list<string> getDevices(),

    /**
    * Get current device
    */
    string getCurrentDevice(),

    /**
    * Set current device
    */
    bool setDevice(1: string devicename),

    /**
    * Get list of existing templates
    */
    list<string> gettempls(),

    /**
    * start matching the given template on. After set
    * getimage starts returning images that contain the match.
    * If parameter is null then template matching is disabled.
    */
    bool setfindtempl(1: string templ),

    /**
    * Save given region as template from given image frame
    * with given name. Return true if saved succesfully.
    */
    bool savetempl(1: i32 id,
                   2: Coordinate topleft,
                   3: Coordinate bottomright,
                   4: string name),

    /**
    * Save given frame as a reference image. Return true
    * if saved succesfully.
    */
    bool savereference(1: i32 id, 2: string name),

    /**
    * Returns status of the lock.
    * False if free, True if locked
    */
    bool locked(),

    /**
    * Handles events from roboio web client
    */
    Response handleEvent(1: Event e),

    /**
     * Returns position of current coordinates as string
     * NOTE: coordinates are returned as string, all the way, because
     * thrift js-generation in version 0.9.0 does not support doubles.
     * client is expected to parse the coordinates from returned string
     * @return string with space separated coordinates: x y z a
     */
    string getposition(),

    /** Sets x y z a position without safety checks - see above */
    bool setposition(1: RobotCoord coord),

    /**
     * Reloads configuration file for DUT
     * @param dutindex index of the dut to reload
     */
    void reloaddutconfig(1: i16 dutindex),
}
