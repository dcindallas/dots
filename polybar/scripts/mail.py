#!/usr/bin/python

import imaplib
obj = imaplib.IMAP4_SSL('imap.dreamhost.com',993)
obj.login('duane@duanecummins.com','Dazed-124')
obj.select()
number = len(obj.search(None, 'UnSeen')[1][0].split())
if number>0:
    print(number)
else:
    print('')
