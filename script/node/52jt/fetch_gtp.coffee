path = require('path')
log4js = require('log4js')
http = require('http')
cheerio = require('cheerio')
fs = require("fs")
Q = require('q')
url = require('url')

baseDir = path.join(path.dirname(__filename), "../../../")

log4js.configure({
  appenders: [
    {type: 'console'},
    {type: 'file', filename: baseDir + '/logs/52jt/fetch_gtp.log'}
  ]
})
logger = log4js.getLogger()

if typeof String.prototype.endsWith != 'function'
  String.prototype.endsWith = (suffix) ->
    @indexOf(suffix, this.length - suffix.length) != -1


getLinksFromList = (content)->
  $ = cheerio.load(content)
  $("#singer_content a.graya12").map((index, ele)->
    return {'link': $(ele).attr('href'), 'name': $(ele).text().trim()}
  )


fetchArtist = (id) ->
  deferred = Q.defer()
  logger.info("Fetching artist " + id)
  links = []
  http.get("http://www.52jt.net/singer-list.asp?/gtp_" + id + ".html", (res)->
    content = ''
    res.on('data', (data)->
      content += data
    )
    res.on('end', ->
      regExp = /共(\d+)页/
      match = regExp.exec(content)
      if match?.length != 2
        deferred.reject(id)
        return
      totalPage = match[1]
      if parseInt(totalPage) == 0
        deferred.reject(null)
      $ = cheerio.load(content)
      artistName = $("#singer_title strong").text()
      if parseInt(totalPage) == 1
        deferred.resolve([artistName, getLinksFromList(content)])
      else
        processedCount = 1
        for i in [2..totalPage]
          http.get("http://www.52jt.net/singer-list.asp?/gtp_" + id + "_" + i + ".html", (res)->
            content = ''
            res.on('data', (data)-> content += data)
            res.on('end', ->
              processedCount += 1
              links = links.concat(getLinksFromList(content))
              if processedCount == totalPage
                deferred.resolve([artistName, links])
            )
          ).on('error', (err)->
            logger.error(err)
            processedCount += 1)
    ))
  .on('error', (err)->
    logger.error(err)
    deferred.reject(id))
  deferred.promise

extractDownloadPages = ([artistName,links])->
  promises = for link in links
    deferred = Q.defer()
    do (link, deferred)->
      pageLink = link['link']
      filename = link['name']
      http.get(pageLink, (res)->
        content = ''
        res.on('data', (data)-> content += data)
        res.on('end', ->
          $ = cheerio.load(content)
          downLoadLink = $("#gtp_content a.graya16").attr("href")
          download(downLoadLink, filename, artistName)
          .then(-> deferred.reslove())
          .fail('error',
            (downloadLink)->
              logger.error("Download error:" + downloadLink)
              deferred.reject()
          )
        )
      ).on('error', (err)->
        logger.error(err)
        logger.error("Process error:" + link)
        deferred.reject()
      )
    deferred.promise
  Q.all(promises)


download = (downloadLink, filename, artistName) ->
  deferred = Q.defer()
  logger.info("Downloading " + downloadLink)
  index = downloadLink.lastIndexOf(".")
  extension = downloadLink.substr(index)
  filename = filename + extension
  requestTimer = setTimeout(->
    req.abort()
    logger.error('Request timeout : ' + downloadLink)
    deferred.reject(downloadLink)
  , 20000)
  req = http.get(downloadLink, (res)->
    buf = new Buffer(1024)
    res.on('data', (data)->
      buf = Buffer.concat([buf, data])
    )
    res.on("end", ->
      clearTimeout(requestTimer)
      outputPath = path.join(baseDir, "data", "52jt", "gtp", artistName, filename)
      outputDir = path.join(baseDir, "data", "52jt", "gtp", artistName)
      if not fs.existsSync(outputDir)
        fs.mkdirSync(outputDir)
      fs.writeFileSync(outputPath, buf)
      deferred.resolve()
    )
  )
  .on('error', (err)->
    logger.error(err)
    deferred.reject(downloadLink)
  )
  deferred.promise


plan = Q()
for index in [1..1]
  do (index)->
    plan = plan.then(-> fetchArtist(index))
    .fail((id)-> logger.error("Fetch artist error : " + id))
    .then(extractDownloadPages)


