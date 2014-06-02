# RoboIO, Web UI for test robots
# Copyright (c) 2014, Intel Corporation.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU Lesser General Public License,
# version 2.1, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for
# more details.

import sys
import fmbtandroid

sys.path.append("./gen-py")
sys.path.append("/usr/lib/python2.7/site-packages")

from thrift.transport import TSocket, TTransport
from thrift.protocol  import TBinaryProtocol
from thrift.server    import TServer

from time import sleep
from datetime import datetime

import os
import signal
from PIL import Image as pilimage

from rataservice        import rataservice
from rataservice.ttypes import *

SCREENSHOT = "/tmp/screen.png"

class RataServiceHandler:
  def __init__(self):
    self.first_call = True
    self.useFMBTDevice = True
    try:
      self.d = fmbtandroid.Device()
      self.d.refreshScreenshot().save(SCREENSHOT)
      self.screensize = self.__getimgsize(SCREENSHOT)
      self.d.setScreenshotLimit(10)
      self.d.setScreenshotArchiveMethod("remove")
    except:
      self.useFMBTDevice = False

    # When asking server to match the template being selected set to true
    self.livematching = False

    self.templates = ['template 1', 'template 2', 'template 3', 'template 4']
    self.id  = 0
    self.img = self.__loadimage("./screenshot1.png", True)
    self.img2 = self.__loadimage("./screenshot2.png", True)
    self.resultimg = self.__loadimage("./machinevision-result.png", True)

    self.position   = RobotCoord(x=152,y=385,z=0.9,alfa=0)

  def __getimgsize(self, filename):
    pil = pilimage.open(filename)
    if self.useFMBTDevice and self.d._screenSize == None:
      self.d._screenSize = pil.size
    return pil.size

  def __loadimage(self, filename, resolvesize=False):
    img = Image()
    img.id = self.id
    with open(filename, "rb") as imgfile:
      img.imagedata = imgfile.read()
      if resolvesize:
        size = self.__getimgsize(filename)
        img.width = size[0]
        img.height = size[1]
      else:
        img.width = self.screensize[0]
        img.height = self.screensize[1]
    return img

  def locked(self):
    if self.first_call:
      self.first_call = False
      return True
    else:
      return False

  def getvisualfeeds(self):
    img = None
    if self.useFMBTDevice:
      self.d.refreshScreenshot().save(SCREENSHOT)
      img = self.__loadimage(SCREENSHOT)
    else: # change images for visual feed updates
      if self.id % 2 == 0:
        img = self.img
      else:
        img = self.img2
    sleep(0.5)
    self.id += 1

    feed1 = visualfeed()
    feed1.content = img
    feed1.updated = True
    feed1.message = str(datetime.now())

    if self.livematching:
      feed2 = visualfeed()
      feed2.content = self.resultimg
      feed2.updated = True
      feed2.message = str(datetime.now())

      return [feed1, feed2]

    else:
      return [feed1]

  def setpreviewmatchingmode(self, args):
    print "Set preview matching mode to {}".format(args.enabled)
    self.livematching = args.enabled
    return True

  def gettempls(self):
    return self.templates

  def setfindtempl(self, template):
    if template == None:
      print "Stop matching template"
      self.livematching = False
    else:
      print "Start matching template {}".format(template)
      self.livematching = True

    return True

  def savetempl(self, idx, topleft, bottomright, name):
    print "Save ({},{}) -> ({},{}) from frame {} as template {}".format(topleft.x, topleft.y, bottomright.x, bottomright.y, idx, name)
    self.templates.append(name)
    sleep(0.2)
    return True

  def savereference(self, idx, name):
    print "Save frame {} as reference {}".format(idx, name)
    sleep(0.2)
    return True

  def setVisualDataSource(self, req):
    if req.source_type == VisualSource.CAMTHREAD:
      print "Setting visual data source to CAMTHREAD"
    else:
      print "Setting visual data source to something"

    return True

  def handleEvent(self, event):
    if event.type == EventType.KEYPRESS:
      print "Keycode: {}".format(event.keypress.keyCode)
      if self.useFMBTDevice and event.keypress.character == "h":
        self.d.pressHome()
      elif self.useFMBTDevice and event.keypress.character == "b":
        self.d.pressBack()
      elif self.useFMBTDevice and event.keypress.character == "m":
        self.d.pressMenu()
      elif self.useFMBTDevice and event.keypress.character == "s":
        self.d.pressAppSwitch()
      elif self.useFMBTDevice and event.keypress.character == "u":
        self.d.pressPower()
        self.d.refreshScreenshot()
        sleep(0.2)
        self.d.swipe((0.5, 0.7), "east")
      elif self.useFMBTDevice and event.keypress.keyCode == 39:
        self.d.swipe((0.5, 0.5), "east")
      elif self.useFMBTDevice and event.keypress.keyCode == 37:
        self.d.swipe((0.5, 0.5), "west")
      elif self.useFMBTDevice and event.keypress.keyCode == 40:
        self.d.swipe((0.5, 0.0), "south")
      elif self.useFMBTDevice and event.keypress.keyCode == 38:
        self.d.swipe((0.5, 1.0), "north")

    elif event.type == EventType.MOUSECLICK:
      print "Click: ({}, {})".format(event.click.x, event.click.y)
      if self.useFMBTDevice:
        self.d._conn.sendTap(event.click.x, event.click.y)

    res = Response()
    res.err     = Error.NONE
    res.message = "OK"

    return res

  def getDevices(self):
    devices = ['android']
    for i in range(1,4):
      d = "Device {}".format(i)
      devices.append(d)
    return devices

  def getposition(self):
    pos = "{} {} {} {}".format(self.position.x,
                               self.position.y,
                               self.position.z,
                               self.position.alfa)
    print "Send position: {}".format(pos)
    return pos

  def setposition(self, position):
    self.position = position
    print "Move to position: {} {} {} {}".format(self.position.x,
                                                 self.position.y,
                                                 self.position.z,
                                                 self.position.alfa)
    sleep(0.5)
    return True

  def getCurrentDevice(self):
    return "android"

  def setDevice(self, device):
    print "Selecting device name {}".format(device)
    sleep(10)
    return True

  def reloaddutconfig(self, idx):
    print "Reload config for dut {}".format(idx)
    return

if __name__ == "__main__":
  handler   = RataServiceHandler()
  processor = rataservice.Processor(handler)
  transport = TSocket.TServerSocket(port=9090)
  tfactory  = TTransport.TFramedTransportFactory()
  pfactory  = TBinaryProtocol.TBinaryProtocolFactory()
  server    = TServer.TThreadedServer(processor, transport, tfactory, pfactory)

  print "Server started"
  try:
    server.serve()
  except KeyboardInterrupt:
    os.kill(os.getpid(), signal.SIGKILL)
