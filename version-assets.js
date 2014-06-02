var version  = require('node-version-assets');
var instance = new version({
  assets:     ['public/css/roboio.css', 'public/js/modules/main.js'],
  grepFiles:  ['src/jade/index.jade', 'src/jade/layout.jade'],
  requireJs:  true
});
instance.run();
