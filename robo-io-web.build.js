({
    appDir: 'public-build/',
    baseUrl: 'js/modules',
    dir: 'public-tmp/',
    paths: {
        jquery: '../../../public/js/vendor/jquery.min',
        jcrop:  '../../../public/js/vendor/jquery.Jcrop',
        bacon:  '../../../public/js/vendor/Bacon.min',
        select: '../../../public/js/vendor/select2.min'
    },
    modules: [
        { name: 'app'     },
        { name: 'ui'      },
        { name: 'main'    },
        { name: 'utils'   },
        { name: 'ws'      },
        { name: 'testrun' }
    ]
})
