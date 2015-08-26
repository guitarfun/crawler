path = require('path')
log4js = require('log4js')
http = require('http')
cheerio = require('cheerio')
fs = require("fs")
Q = require('q')
throat = require('throat')(Q)
limitConcurrency = require("../common/limit_concurrency").limitConcurrency


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
  $("#singer_content #gtp_detail a.graya12").map((index, ele)->
    {'link': $(ele).attr('href'), 'name': $(ele).text().trim()}
  ).get()


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
        logger.error("Pagination format error")
        deferred.reject()
        return
      totalPage = parseInt(match[1])
      logger.info("Total page:" + totalPage)

      if totalPage == 0
        logger.info("Empty artist")
        deferred.reject()
      $ = cheerio.load(content)
      artistName = $("#singer_title strong").text()
      if totalPage == 1
        deferred.resolve([artistName, getLinksFromList(content)])
      else
        links = getLinksFromList(content)
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
    deferred.reject())
  deferred.promise.timeout(60000)


extractDownloadPages = (artistName, links)->
  throatPromise = limitConcurrency((link)->
    pageLink = link['link']
    filename = link['name']
    extractDownloadLink(pageLink)
    .then((downloadLink)-> download(downloadLink, filename, artistName))
    .catch((err)->
      logger.error("Process error:" + pageLink)
      logger.error(err) if err?)
  , 10)
  promises = (throatPromise(link) for link in links)
  Q.allSettled(promises)


extractDownloadLink = (link)->
  deferred = Q.defer()
  content = ''
  http.get(link, (res)->
    content = ''
    res.on('data', (data)-> content += data)
    res.on('end', ->
      $ = cheerio.load(content)
      downLoadLink = $("#gtp_content a.graya16").attr("href")
      if not downLoadLink
        deferred.reject()
      else
        deferred.resolve(downLoadLink)
    )
  ).on('error', (err)->
    logger.error(err)
    deferred.reject()
  )
  deferred.promise.timeout(30000)

download = (downloadLink, filename, artistName) ->
  deferred = Q.defer()
  logger.info("Downloading " + downloadLink)
  index = downloadLink.lastIndexOf(".")
  extension = downloadLink.substr(index)
  filename = filename + extension
  http.get(downloadLink, (res)->
    buf = new Buffer(1024)
    res.on('data', (data)->
      buf = Buffer.concat([buf, data])
    )
    res.on("end", ->
      outputPath = path.join(baseDir, "data", "52jt", "gtp", artistName, filename)
      outputDir = path.join(baseDir, "data", "52jt", "gtp", artistName)
      if not fs.existsSync(outputDir)
        fs.mkdirSync(outputDir)
      fs.writeFile(outputPath, buf, (err)->
        if err?
          logger.error(err)
          return
        deferred.resolve()
      )
    )
  )
  .on('error', (err)->
    logger.error(err)
    deferred.reject()
  )
  deferred.promise.timeout(30000)


plan = Q()
for index in [217..6000]
  plan = plan.then(fetchArtist.bind(null, index)).spread(extractDownloadPages).catch((ex)->logger.info(ex) if ex?)
plan.done()


