#!/usr/bin/python

import requests
import os.path

#path to polynews script

save_path = '/home/duane/.config/polybar/scripts/polynews/'

#get your api key at https://newsapi.org/

api_key = "37fb45999c3340c980e930a732764bf5"

#find sources & country codes at https://newsapi.org/sources

sources = "cnn,reuters,associated-press"
country = ""

try:
    data = requests.get('https://newsapi.org/v2/top-headlines?apiKey='+api_key+'&sources='+sources+'&country='+country).json()

    sourceName = data['articles'][0]['source']['name']
    title = data['articles'][0]['title']
    url = data['articles'][0]['url']

    print(sourceName+': '+title)

    path = os.path.join(save_path,"current_url.txt")
    f = open(path, "w")
    f.write(url)
    f.close()


except requests.exceptions.RequestException as e:
    print ('Something went wrong!')
