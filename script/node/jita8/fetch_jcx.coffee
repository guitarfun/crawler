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
    {type: 'file', filename: baseDir + '/logs/jita8/fetch_jcx.log'}
  ]
})
logger = log4js.getLogger()


fetchList = (page) ->
  deferred = Q.defer()
  logger.info("Fetching page " + page)
  http.get("http://jitapu.jita8.com/chaxun.asp?move=" + page + "&leibie=muse", (res)->
    content = ''
    res.on('data', (data)-> content += iconv.decode(data, "GBK"))
    res.on('end', -> deferred.resolve(content))
  ).on('error', deferred.reject)
  deferred.promise

processListContent = (content)->
  $ = cheerio.load(content)
  names = $('td.style156 a').filter((index, ele)-> $(ele).text().indexOf(".jcx") != -1).map((index, ele)-> $(ele).text() + ".rar")
  processors = (download(name) for name in names)
  Q.all(processors)


download = (fileName)->
  deferred = Q.defer()
  link = "http://jitapu1.jita8.com/" + encodeURI("吉他谱") + "/" + encodeURI("muse格式") + "/" + encodeURI(fileName)
  logger.info("Downloading " + link)
  http.get(link, (res)->
    buf = new Buffer(1024)
    res.on('data', (data)->
      buf = Buffer.concat([buf, data])
    )
    res.on("end", ->
      outputPath = path.join(baseDir, "data", "jita8", "jcx", fileName)
      fs.writeFileSync(outputPath, buf)
      deferred.resolve()
    )
  )
  .on('error', deferred.reject)
  deferred.promise


plan = Q()
for index in [1..33]
  plan = plan.then(fetchList.bind(null, index))
  .fail((e)-> logger.error(e))
  .then(processListContent)
  .fail((e)-> logger.error(e))


