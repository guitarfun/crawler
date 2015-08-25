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
    {type: 'file', filename: baseDir + '/logs/jita8/fetch_midi.log'}
  ]
})
logger = log4js.getLogger()


fetchList = (page) ->
  deferred = Q.defer()
  logger.info("Fetching page " + page)
  http.get("http://jitapu.jita8.com/chaxun.asp?move=" + page + "&leibie=mid", (res)->
    content = ''
    res.on('data', (data)-> content += iconv.decode(data, "GBK"))
    res.on('end', -> deferred.resolve(content))
  ).on('error', -> deferred.reject(page))
  deferred.promise

processListContent = (content)->
  $ = cheerio.load(content)
  processors = $('td.style156 a').map((index, ele)->
    extractFileLink("http://jitapu.jita8.com/" + $(ele).attr('href'), $(ele).text())
    .fail((link)-> logger.error("Extract link error: " + link))
    .then(download)
    .fail((link)-> logger.error("Download error: " + link)))
  Q.all(processors)


extractFileLink = (link, name)->
  deferred = Q.defer()
  http.get(link, (res)->
    content = ''
    res.on('data', (data)-> content += iconv.decode(data, "GBK"))
    res.on('end', ->
      regExp = /javascript:mm\('(.+?)'/
      match = regExp.exec(content)
      if match?.length != 2
        deferred.reject(link)
        return
      downloadLink = match[1]
      deferred.resolve([downloadLink, name]))
  ).on('error', -> deferred.reject(link))
  deferred.promise


download = ([downloadLink, name]) ->
  deferred = Q.defer()
  logger.info("Downloading " + downloadLink)
  http.get(encodeURI(downloadLink), (res)->
    buf = new Buffer(1024)
    res.on('data', (data)->
      buf = Buffer.concat([buf, data])
    )
    res.on("end", ->
      outputPath = path.join(baseDir, "data", "jita8", "midi", name + ".rar")
      fs.writeFileSync(outputPath, buf)
      deferred.resolve()
    )
  )
  .on('error', -> deferred.reject(downloadLink))
  deferred.promise


plan = Q()
for index in [1..125]
  plan = plan.then(fetchList.bind(null, index))
  .fail((page)-> logger.error("Fetch list error. Page : " + page))
  .then(processListContent)


