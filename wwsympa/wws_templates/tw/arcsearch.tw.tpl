<!-- RCS Identication ; $Revision$ ; $Date$ -->

<H2>在存檔中搜索的結果
<A HREF="[path_cgi]/arc/[list]/[archive_name]"><FONT COLOR="[dark_color]">[list]</font></a>: </H2>

<P>查詢域:
[FOREACH u IN directories]
<A HREF="[path_cgi]/arc/[list]/[u]"><FONT COLOR="[dark_color]">[u]</font></a> - 
[END]
</P>

查詢參數的應用範圍 <b> &quot;[key_word]&quot;</b>
<I>

[IF how=phrase]
	(本句話，
[ELSIF how=any]
	(所有的詞，
[ELSE]
	(每個詞，
[ENDIF]

<i>

[IF case]
	不區分大小寫
[ELSE]
	區分大小寫
[ENDIF]

[IF match]
	和檢查詞的部分)</i>
[ELSE]
	和檢查整個詞)</i>
[ENDIF]
<p>

<HR>

[IF age]
	<B>最新郵件優先</b><P>
[ELSE]
	<B>最舊郵件優先</b><P>
[ENDIF]

[FOREACH u IN res]
	<DT><A HREF=[u->file]>[u->subj]</A> -- <EM>[u->date]</EM><DD>[u->from]<PRE>[u->body_string]</PRE>
[END]

<DL>
<B>結果</b>
<DT><B>在 [num] 中選中了 [searched] 個郵件 ...</b><BR>

[IF body]
	<DD>根據郵件<i>內容</i>有 <B>[body_count]</b> 個命中<BR>
[ENDIF]

[IF subj]
	<DD>根據郵件<i>主題</i>有 <B>[subj_count]</b> 個命中<BR>
[ENDIF]

[IF from]
	<DD>根據郵件<i>發信人</i>有 <B>[from_count]</b> 個命中<BR>
[ENDIF]

[IF date]
	<DD>根據郵件<i>日期</i>有 <B>[date_count]</b> 個命中<BR>
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
	<INPUT NAME=action_arcsearch TYPE=submit VALUE="繼續查詢">
[ENDIF]

<INPUT NAME=action_arcsearch_form TYPE=submit VALUE="新的查詢">
</FORM>
<HR>
基於<Font size=+1 color="[dark_color]"><i><A HREF="http://www.mhonarc.org/contrib/marc-search/">Marc-Search</a></i></font>，<B>MHonArc</B>歸檔的搜索引擎<p>


<A HREF="[path_cgi]/arc/[list]/[archive_name]"><B>回到 Archive [archive_name] 
</B></A><br>
