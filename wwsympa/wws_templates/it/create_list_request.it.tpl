
<FORM ACTION="[path_cgi]" METHOD=POST>

<P>
<TABLE>
 <TR>
   <TD NOWRAP><B>Nome della lista:</B></TD>
   <TD><INPUT TYPE="text" NAME="listname" SIZE=30 VALUE="[saved->listname]"></TD>
   <TD><img src="/icons/unknown.gif" alt="il nome della lista, non il suo indirizzo"></TD>
 </TR>
 
 <TR>
   <TD NOWRAP><B>Proprietario:</B></TD>
   <TD><I>[user->email]</I></TD>
   <TD><img src="/icons/unknown.gif" alt="non sei utente privilegiato di questa lista"></TD>
 </TR>

 <TR>
   <TD valign=top NOWRAP><B>Tipo di lista :</B></TD>
   <TD>
     <MENU>
[FOREACH template IN list_list_tpl]
     <INPUT TYPE="radio" NAME="template" Value="[template->NAME]"
     [IF template->selected]
       CHECKED
     [ENDIF]
     > [template->NAME]<BR>
     [PARSE template->comment]
     <BR>
[END]
     </MENU>
    </TD>
    <TD valign=top><img src="/icons/unknown.gif" alt="Il tipo di lista consiste in un profilo. I parametri saranno modificabili successivamente"></TD>
 </TR>
 <TR>
   <TD NOWRAP><B>Soggetto:</B></TD>
   <TD><INPUT TYPE="text" NAME="subject" SIZE=60 VALUE="[saved->subject]"></TD>
   <TD><img src="/icons/unknown.gif" alt="Soggetto della lista"></TD>
 </TR>
 <TR>
   <TD NOWRAP><B>Argomenti:</B></TD>
   <TD><SELECT NAME="topics">
	<OPTION VALUE="">--Scegli un argomento--
	[FOREACH topic IN list_of_topics]
	  <OPTION VALUE="[topic->NAME]"
	  [IF topic->selected]
	    SELECTED
	  [ENDIF]
	  >[topic->title]
	  [IF  topic->sub]
	  [FOREACH subtopic IN topic->sub]
	     <OPTION VALUE="[topic->NAME]/[subtopic->NAME]">[topic->title] / [subtopic->title]
	  [END]
	  [ENDIF]
	[END]
     </SELECT>
   </TD>
  <TD valign=top><img src="/icons/unknown.gif" alt="List classification in the directory"></TD>
 </TR>
 <TR>
   <TD valign=top NOWRAP><B>Descrizione:</B></TD>
   <TD><TEXTAREA COLS=60 ROWS=10 NAME="info">[saved->info]</TEXTAREA></TD>
   <TD valign=top><img src="/icons/unknown.gif" alt="Un po' di linee di descrizione"></TD>
 </TR>

<TR><TD COLSPAN=2 ALIGN="center">
<TABLE><TR><TD BGCOLOR="--LIGHT_COLOR--">
<INPUT TYPE="submit" NAME="action_create_list" VALUE="Spedisci la tua richiesta di creazione"></TD></TR></TABLE
</TD></TR>
</TABLE>



</FORM>




