From: [from]
To: Moderatori della lista [list->name] <[list->name]-editor@[list->host]>
Subject: Messaggio da approvare
Reply-To: [conf->email]@[conf->host]
Mime-version: 1.0
Content-Type: multipart/mixed; boundary="[boundary]"

--[boundary]
Content-Type: text/plain; charset=iso-8859-1
Content-transfer-encoding: 8bit

[IF method=md5]
Per inoltrare il messaggio allegato alla lista '[list->name]' :
mailto:[conf->email]@[conf->host]?subject=DISTRIBUTE%20[list->name]%20[modkey]

Per respingerlo (sara' cancellato) :
mailto:[conf->email]@[conf->host]?subject=REJECT%20[list->name]%20[modkey]
[ENDIF]

--[boundary]
Content-Type: message/rfc822
Content-Transfer-Encoding: 8bit
Content-Disposition: inline

[INCLUDE msg]

--[boundary]--

