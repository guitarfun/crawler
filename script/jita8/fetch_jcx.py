# -*- coding: utf-8 -*-

import urllib2
import urllib
from BeautifulSoup import BeautifulSoup
import os
import logging

logging.basicConfig(level=logging.DEBUG,
                    format='%(asctime)s %(filename)s[line:%(lineno)d] %(levelname)s %(message)s',

                    datefmt='%Y-%m-%d %H:%M:%S')

base_dir = os.path.join(os.path.dirname(__file__), '../')

list_base_url = "http://jitapu.jita8.com/chaxun.asp?move=%d&leibie=muse"
download_base_url = "http://jitapu1.jita8.com/" + urllib.quote("吉他谱") + "/" + urllib.quote("muse格式") + "/"

page = 6
while True:
    list_url = list_base_url % page
    logging.info("Get list page " + list_url)
    content = urllib2.urlopen(list_url).read().decode("gbk")
    soup = BeautifulSoup(content)
    tds = soup.findAll('td', attrs={'class': "style156"})
    if len(tds) == 0:
        break
    for td in tds:
        for link in td.findAll('a'):
            link_text = link.text.strip().encode("utf-8")
            if link_text.find(".jcx") != -1:
                link_text += ".rar"
                download_url = download_base_url + urllib.quote(link_text)
                logging.info("Downloading " + download_url)
                try:
                    file_content = urllib2.urlopen(download_url).read()
                except urllib2.HTTPError, ex:
                    logging.error(ex)
                    continue
                with open(os.path.join(base_dir, "data", "jita8", "jcx", link_text), "w") as file_obj:
                    file_obj.write(file_content)
    page += 1
