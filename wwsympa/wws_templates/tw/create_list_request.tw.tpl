<!-- RCS Identication ; $Revision$ ; $Date$ -->


<FORM ACTION="[path_cgi]" METHOD=POST>

<P>
<TABLE>
 <TR>
   <TD NOWRAP><B> Mailing List 名字:</B></TD>
   <TD><INPUT TYPE="text" NAME="listname" SIZE=30 VALUE="[saved->listname]"></TD>
   <TD><img src="[icons_url]/unknown.png" alt=" Mailing List 名；注意，不是它的地址!"></TD>
 </TR>
 
 <TR>
   <TD NOWRAP><B>所有者:</B></TD>
   <TD><I>[user->email]</I></TD>
   <TD><img src="[icons_url]/unknown.png" alt="您是這個 Mailing List 的Privilege所有者"></TD>
 </TR>

 <TR>
   <TD valign=top NOWRAP><B> Mailing List 類型: </B></TD>
   <TD>
     <MENU>
  [FOREACH template IN list_list_tpl]
     <INPUT TYPE="radio" NAME="template" Value="[template->NAME]"
     [IF template->selected]
       CHECKED
     [ENDIF]
     > [template->NAME]<BR>
     <BLOCKQUOTE>
     [PARSE template->comment]
     </BLOCKQUOTE>
     <BR>
  [END]
     </MENU>
    </TD>
    <TD valign=top><img src="[icons_url]/unknown.png" alt=" Mailing List 類型是參數集設定。可以在 Mailing List 創建後編輯參數"></TD>
 </TR>
 <TR>
   <TD NOWRAP><B>主題:</B></TD>
   <TD><INPUT TYPE="text" NAME="subject" SIZE=60 VALUE="[saved->subject]"></TD>
   <TD><img src="[icons_url]/unknown.png" alt="這是 Mailing List 的主題"></TD>
 </TR>
 <TR>
   <TD NOWRAP><B>話題:</B></TD>
   <TD><SELECT NAME="topics">
	<OPTION VALUE="">--選擇話題--
	[FOREACH topic IN list_of_topics]
	  <OPTION VALUE="[topic->NAME]"
	  [IF topic->selected]
	    SELECTED
	  [ENDIF]
	  >[topic->title]
	  [IF topic->sub]
	  [FOREACH subtopic IN topic->sub]
	     <OPTION VALUE="[topic->NAME]/[subtopic->NAME]">[topic->title] / [subtopic->title]
	  [END]
	  [ENDIF]
	[END]
	<OPTION VALUE="other">其它
     </SELECT>
   </TD>
   <TD valign=top><img src="[icons_url]/unknown.png" alt="目錄中的 Mailing List 分類"></TD>
 </TR>

 <TR>
   <TD valign=top NOWRAP><B>描述:</B></TD>
   <TD><TEXTAREA COLS=60 ROWS=10 NAME="info">[saved->info]</TEXTAREA></TD>
   <TD valign=top><img src="[icons_url]/unknown.png" alt="幾行對 Mailing List 的描述文字"></TD>
 </TR>

 <TR>
   <TD COLSPAN=2 ALIGN="center">
    <TABLE>
     <TR>
      <TD BGCOLOR="[light_color]">
<INPUT TYPE="submit" NAME="action_create_list" VALUE="確認您的創建請求">
      </TD>
     </TR></TABLE>
</TD></TR>
</TABLE>



</FORM>




