<!-- RCS Identication ; $Revision$ ; $Date$ -->

[IF help_topic]
 [PARSE help_template]

[ELSE]
<BR>
WWSympa V�m poskytuje p��stup k Va�emu prost�ed� na konferen�n�m serveru
<B>[conf->email]@[conf->host]</B>.
<BR><BR>
Funkce, ekvivalentn� k p��kaz�m v po�t�, jsou dostupn� ve vrchn� �rovni
u�ivatelsk�ho rozhran�. WWSympa poskytuje prost�ed� s p��stupem k n�sleduj�c�m
funkc�m:

<UL>
<LI><A HREF="[path_cgi]/pref">Nastaven�</A> : u�ivatelsk� nastaven�. Je dostupn� pouze p�ihl�en�m u�ivatel�m

<LI><A HREF="[path_cgi]/lists">Ve�ejn� konference</A> : adres�� konferenc� dostupn�ch na serveru

<LI><A HREF="[path_cgi]/which">Va�e �lenstv�</A> : Va�e prost�ed� jako �len nebo vlastn�k

<LI><A HREF="[path_cgi]/loginrequest">P�ihl�en�</A> / <A HREF="[path_cgi]/logout">Odhl�en�</A> : P�ihl�en� / Odhl�en� z WWSympa.
</UL>

<H2>P�ihl�en�</H2>

[IF auth=classic]
P�i ov��ov�n� toto�nosti (<A HREF="[path_cgi]/loginrequest">p�ihl�en�</A>), poskytujete Va�i emailovou adresu a heslo.
<BR><BR>
Jakmile jste prov��en, je vytvo�ena <I>"cookie"</I> kter� obsahuje
informace pro udr�en� Va�� toto�nosti. Doba trv�n� <I>cookie</I> 
se d� zm�nit v <A HREF="[path_cgi]/pref">Nastaven�</A>. 

<BR><BR>
[ENDIF]
M��ete se odhl�sit (vymaz�n�m <I>cookie</I>) kdykoli pomoc� funkce
<A HREF="[path_cgi]/logout">logout</A>.


<H5>Probl�my p�i p�ihl�en�</H5>

<I>Nejsem �lenem konference</I><BR>
To znamen�, �e nejste registrov�n v datab�zi u�ivatel� a tedy se nem��ete 
p�ihl�sit. Jakmile se p�ihl�s�te do n�jak� konference, WWSympa V�m p�id�l�
�vodn� heslo.
<BR><BR>

<I>Jsem �lenem v konferenci ale nem�m heslo</I><BR>
Pro z�sk�n� hesla : 
<A HREF="[path_cgi]/remindpasswd">[path_cgi]/remindpasswd</A>
<BR><BR>

<I>Zapomn�l jsem heslo</I><BR>

WWSympa V�m za�le heslo emailem :
<A HREF="[path_cgi]/remindpasswd">[path_cgi]/remindpasswd</A>

<P>

Kontakt na spr�vce : <A HREF="mailto:listmaster@[conf->host]">listmaster@[conf->host]</A>
[ENDIF]
