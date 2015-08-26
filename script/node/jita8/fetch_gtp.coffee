path = require('path')
log4js = require('log4js')
http = require('http')
iconv = require('iconv-lite')
cheerio = require('cheerio')
fs = require("fs")
Q = require('q')

baseDir = path.join(path.dirname(__filename), "../../../")

log4js.configure({
  appenders: [
    {type: 'console'},
    {type: 'file', filename: baseDir + '/logs/jita8/fetch_gtp.log'}
  ]
})
logger = log4js.getLogger()


fetchList = (page) ->
  deferred = Q.defer()
  logger.info("Fetching page " + page)
  http.get("http://jitapu.jita8.com/chaxun.asp?move=" + page + "&leibie=gtp", (res)->
    content = ''
    res.on('data', (data)-> content += iconv.decode(data, "GBK"))
    res.on('end', -> deferred.resolve(content))
  ).on('error', (err)->
    logger.error(err)
    deferred.reject())
  deferred.promise.timeout(60000)

processListContent = (content)->
  $ = cheerio.load(content)
  processors = for ele in $('td.style156 a').get()
    do (ele)->
      extractFileLink("http://jitapu.jita8.com/" + $(ele).attr('href'), $(ele).text())
      .spread(download).catch((err)->
        logger.error(err) if err?
        logger.error("Error processing:" + $(ele).attr('href'))
      )
  Q.allSettled(processors)


extractFileLink = (link, name)->
  deferred = Q.defer()
  http.get(link, (res)->
    content = ''
    res.on('data', (data)-> content += iconv.decode(data, "GBK"))
    res.on('end', ->
      regExp = /javascript:mm\('(.+?)'/
      match = regExp.exec(content)
      if match?.length != 2
        deferred.reject()
        return
      downloadLink = match[1]
      deferred.resolve([downloadLink, name]))
  ).on('error', (err)->
    logger.error(err)
    deferred.reject())
  deferred.promise.timeout(60000)


download = (downloadLink, name) ->
  deferred = Q.defer()
  logger.info("Downloading " + downloadLink)
  requestTimer = setTimeout(->
    req.abort()
    logger.error('Request timeout : ' + downloadLink)
    deferred.reject()
  , 20000)
  req = http.get(encodeURI(downloadLink), (res)->
    buf = new Buffer(1024)
    res.on('data', (data)->
      buf = Buffer.concat([buf, data])
    )
    res.on("end", ->
      clearTimeout(requestTimer)
      outputPath = path.join(baseDir, "data", "jita8", "gtp", name + ".rar")
      fs.writeFileSync(outputPath, buf)
      deferred.resolve()
    )
  )
  .on('error', (err)->
    logger.error(err)
    deferred.reject())
  deferred.promise.timeout(60000)


plan = Q()
for index in [1131..1422]
  plan = plan.then(fetchList.bind(null, index))
  .then(processListContent)
  .catch((err)-> logger.error(err) if err?)



