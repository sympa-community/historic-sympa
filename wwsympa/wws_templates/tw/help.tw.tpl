<!-- RCS Identication ; $Revision$ ; $Date$ -->

[IF help_topic]
 [PARSE help_template]

[ELSE]
<BR>
±z¥i¥H¦b³o¸Ì³X°Ý¶l¥ó Mailing List  Server  <B>[conf->email]@[conf->host]</B>¡C
<BR><BR>
©M Sympa ¾÷¾¹¤H©R¥O(³q¹L¶l¥ó¶i¦æ)¬Û¦Pªº¥\¯à¥i¥H±q°ª¯Å§Oªº¥Î¤á¬É­±¤W¨Ï¥Î¡C
WWSympa ´£¨Ñ¥i¦Û­qªºÀô¹Ò¡A¥i¨Ï¥Î¥H¤U¥\¯à: 

<UL>
<LI><A HREF="[path_cgi]/pref">¿ï¶µ</A>: ¥Î¤á¿ï¶µ¡C¶È´£¨Ñµ¹½T»{¨­¥÷ªº¥Î¤á¡C

<LI><A HREF="[path_cgi]/lists">¤½¶} Mailing List </A>:  Server ¤W´£¨Ñªº¤½¶} Mailing List ¡C

<LI><A HREF="[path_cgi]/which">±z­q¾\ªº Mailing List </A>: ±z§@¬°­q¾\ªÌ©Î¾Ö¦³ªÌªºÀô¹Ò¡C

<LI><A HREF="[path_cgi]/loginrequest"> Login </A>©Î<A HREF="[path_cgi]/logout">Logout</A>: ±q WWSympa ¤W Login ©Î°h¥X¡C
</UL>

<H2> Login </H2>

[IF auth=classic]
¦bÅçµý¨­¥÷(<A HREF="[path_cgi]/loginrequest"> Login </A>)®É¡A½Ð´£¨Ñ±zªº Email ¦a§}©M¬ÛÀ³ªº±K½X¡C
<BR><BR>
¤@¥¹³q¹LÅçµý¡A¤@­Ó¥]§t±z Login °T®§ªº <I>cookie</I> ¨Ï±z¯à°÷«ùÄò³X°Ý WWSympa¡C
³o­Ó <I>cookie</I> ªº¥Í¦s´Á¥i¥H¦b±zªº<A HREF="[path_cgi]/pref">¿ï¶µ</A>¤¤«ü©w¡C

<BR><BR>
[ENDIF]

±z¥i¥H¦b¥ô¦ó®É­Ô¨Ï¥Î<A HREF="[path_cgi]/logout">Logoutø</>¥\¯à Logout <I>cookie</I>)¡C

<H5> Login °ÝÃD</H5>

<I>§Ú¤£¬O Mailing List ªº­q¾\ªÌ</I><BR>
©Ò¥H±z¨S¦³¦b Sympa ªº¥Î¤á Database ¤¤µn°O¥BµLªk Login ¡C
¦pªG±z­q¾\¤F¤@­Ó Mailing List ¡AWWSympa ±Nµ¹±z¤@­Óªì©l±K½X¡C
<BR><BR>

<I>§Ú¬O¦Ü¤Ö¤@­Ó Mailing List ªº­q¾\ªÌ¡A¦ý¬O§Ú¨S¦³±K½X</I><BR>
­n¦¬¨ì±K½X:
<A HREF="[path_cgi]/remindpasswd">[path_cgi]/remindpasswd</A>
<BR><BR>

<I>§Ú§Ñ°O¤F±K½X</I><BR>
WWSympa ¥i¥H³q¹L¹q¤l¶l¥ó¨Ó§i¶D±z±K½X:
<A HREF="[path_cgi]/remindpasswd">[path_cgi]/remindpasswd</A>

<P>

¦pªG­nÁpµ¸ Server ºÞ²z­û: <A HREF="mailto:listmaster@[conf->host]">listmaster@[conf->host]</A>
[ENDIF]













