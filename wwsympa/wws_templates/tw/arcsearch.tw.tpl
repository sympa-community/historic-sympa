<!-- RCS Identication ; $Revision$ ; $Date$ -->

<H2>�b�s�ɤ��j�������G
<A HREF="[path_cgi]/arc/[list]/[archive_name]"><FONT COLOR="[dark_color]">[list]</font></a>: </H2>

<P>�d�߰�:
[FOREACH u IN directories]
<A HREF="[path_cgi]/arc/[list]/[u]"><FONT COLOR="[dark_color]">[u]</font></a> - 
[END]
</P>

�d�߰Ѽƪ����νd�� <b> &quot;[key_word]&quot;</b>
<I>

[IF how=phrase]
	(���y�ܡA
[ELSIF how=any]
	(�Ҧ������A
[ELSE]
	(�C�ӵ��A
[ENDIF]

<i>

[IF case]
	���Ϥ��j�p�g
[ELSE]
	�Ϥ��j�p�g
[ENDIF]

[IF match]
	�M�ˬd��������)</i>
[ELSE]
	�M�ˬd��ӵ�)</i>
[ENDIF]
<p>

<HR>

[IF age]
	<B>�̷s�l���u��</b><P>
[ELSE]
	<B>���¶l���u��</b><P>
[ENDIF]

[FOREACH u IN res]
	<DT><A HREF=[u->file]>[u->subj]</A> -- <EM>[u->date]</EM><DD>[u->from]<PRE>[u->body_string]</PRE>
[END]

<DL>
<B>���G</b>
<DT><B>�b [num] ���襤�F [searched] �Ӷl�� ...</b><BR>

[IF body]
	<DD>�ھڶl��<i>���e</i>�� <B>[body_count]</b> �өR��<BR>
[ENDIF]

[IF subj]
	<DD>�ھڶl��<i>�D�D</i>�� <B>[subj_count]</b> �өR��<BR>
[ENDIF]

[IF from]
	<DD>�ھڶl��<i>�o�H�H</i>�� <B>[from_count]</b> �өR��<BR>
[ENDIF]

[IF date]
	<DD>�ھڶl��<i>���</i>�� <B>[date_count]</b> �өR��<BR>
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
	<INPUT NAME=action_arcsearch TYPE=submit VALUE="�~��d��">
[ENDIF]

<INPUT NAME=action_arcsearch_form TYPE=submit VALUE="�s���d��">
</FORM>
<HR>
���<Font size=+1 color="[dark_color]"><i><A HREF="http://www.mhonarc.org/contrib/marc-search/">Marc-Search</a></i></font>�A<B>MHonArc</B>�k�ɪ��j������<p>


<A HREF="[path_cgi]/arc/[list]/[archive_name]"><B>�^�� Archive [archive_name] 
</B></A><br>
