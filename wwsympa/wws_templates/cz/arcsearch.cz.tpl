<!-- RCS Identication ; $Revision$ ; $Date$ -->

<H2>V�sledek Va�eho hled�n� v arch�vu
<A HREF="[path_cgi]/arc/[list]/[archive_name]"><FONT COLOR="[dark_color]">[list]</font></a> : </H2>

<P>Pole hled�n� : 
[FOREACH u IN directories]
<A HREF="[path_cgi]/arc/[list]/[u]"><FONT COLOR="[dark_color]">[u]</font></a> - 
[END]
</P>

Parametry toho hled�n� <b> &quot;[key_word]&quot;</b> 
<I>

[IF how=phrase]
	(Tato v�ta, 
[ELSIF how=any]
	(V�echny slova, 
[ELSE]
	(Jak�koli slovo, 
[ENDIF]

<i>

[IF case]
	naz�visle na velikosti p�smen 
[ELSE]
	rozli�ovat velikost p�smen 
[ENDIF]

[IF match]
	sta�� za��tek slova)</i>
[ELSE]
	mus� b�t cel� slovo)</i>
[ENDIF]
<p>

<HR>

[IF age]
	<B>Za��t od nejnov�j��ch zpr�v</b><P>
[ELSE]
	<B>Za�it od nejstar��ch zpr�v</b><P>
[ENDIF]

[FOREACH u IN res]
	<DT><A HREF=[u->file]>[u->subj]</A> -- <EM>[u->date]</EM><DD>[u->from]<PRE>[u->body_string]</PRE>
[END]

<DL>
<B>V�sledek</b>
<DT><B>[searched] zpr�v vybr�no z [num]...</b><BR>

[IF body]
	<DD><B>[body_count]</b> shod v <i>t�le</i> zpr�vy<BR>
[ENDIF]

[IF subj]
	<DD><B>[subj_count]</b> shod v <i>subjektu</i> zpr�vy<BR>
[ENDIF]

[IF from]
	<DD><B>[from_count]</b> shod v poli <i>From</i><BR>
[ENDIF]

[IF date]
	<DD><B>[date_count]</b> shod v poli <i>Date</i><BR>
[ENDIF]

</dl>

<FORM METHOD=POST ACTION="[path_cgi]">
<INPUT TYPE=hidden NAME=list		 VALUE="[list]">
<INPUT TYPE=hidden NAME=archive_name VALUE="[archive_name]">
<INPUT TYPE=hidden NAME=key_word     VALUE="[key_word]">
<INPUT TYPE=hidden NAME=how          VALUE="[how]">
<INPUT TYPE=hidden NAME=age          VALUE="[age]">
<INPUT TYPE=hidden NAME=case         VALUE="[case]">
<INPUT TYPE=hidden NAME=match        VALUE="[match]">
<INPUT TYPE=hidden NAME=limit        VALUE="[limit]">
<INPUT TYPE=hidden NAME=body_count   VALUE="[body_count]">
<INPUT TYPE=hidden NAME=date_count   VALUE="[date_count]">
<INPUT TYPE=hidden NAME=from_count   VALUE="[from_count]">
<INPUT TYPE=hidden NAME=subj_count   VALUE="[subj_count]">
<INPUT TYPE=hidden NAME=previous     VALUE="[searched]">

[IF body]
	<INPUT TYPE=hidden NAME=body Value="[body]">
[ENDIF]

[IF subj]
	<INPUT TYPE=hidden NAME=subj Value="[subj]">
[ENDIF]

[IF from]
	<INPUT TYPE=hidden NAME=from Value="[from]">
[ENDIF]

[IF date]
	<INPUT TYPE=hidden NAME=date Value="[date]">
[ENDIF]

[FOREACH u IN directories]
	<INPUT TYPE=hidden NAME=directories Value="[u]">
[END]

[IF continue]
	<INPUT NAME=action_arcsearch TYPE=submit VALUE="Pokra�ovat ve hled�n�">
[ENDIF]

<INPUT NAME=action_arcsearch_form TYPE=submit VALUE="Nov� hled�n�">
</FORM>
<HR>
Zalo�eno na <Font size=+1 color="[dark_color]"><i><A HREF="http://www.mhonarc.org/contrib/marc-search/">Marc-Search</a></i></font>, vyhled�vac�m stroji<B>MHonArc</B> arch�v�<p>


<A HREF="[path_cgi]/arc/[list]/[archive_name]"><B>N�vrat k arch�vu [archive_name] 
</B></A><br>
