
<FORM ACTION="[path_cgi]" METHOD=POST>

<P>
<TABLE>
 <TR>
   <TD NOWRAP><B>Nombre de la Lista:</B></TD>
   <TD><INPUT TYPE="text" NAME="listname" SIZE=30 VALUE="[saved->listname]"></TD>
   <TD><img src="/icons/unknown.gif" alt="nombre de la lista ; no su direcci�n!"></TD>
 </TR>
 
 <TR>
   <TD NOWRAP><B>Propietario:</B></TD>
   <TD><I>[user->email]</I></TD>
   <TD><img src="/icons/unknown.gif" alt="Vd. es el propietaro de esta lista"></TD>
 </TR>

 <TR>
   <TD valign=top NOWRAP><B>Tipo de Lista :</B></TD>
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
    <TD valign=top><img src="/icons/unknown.gif" alt="El tipo de lista es un conjunto de par�metros. Estos, son editables, una vez que la lista haya sido creada"></TD>
 </TR>
 <TR>
   <TD NOWRAP><B>Tema:</B></TD>
   <TD><INPUT TYPE="text" NAME="subject" SIZE=60 VALUE="[saved->subject]"></TD>
   <TD><img src="/icons/unknown.gif" alt="El tema de la lista"></TD>
 </TR>
 <TR>
   <TD NOWRAP><B>T�picos:</B></TD>
   <TD><SELECT NAME="topics">
	<OPTION VALUE="" >--Seleccione un t�pico--
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
     </SELECT>
   </TD>
   <TD valign=top><img src="/icons/unknown.gif" alt="Clasificaci�n de la lista en el directorio"></TD>
 </TR>
 <TR>
   <TD valign=top NOWRAP><B>Descripci�n:</B></TD>
   <TD><TEXTAREA COLS=60 ROWS=10 NAME="info">[saved->info]</TEXTAREA></TD>
   <TD valign=top><img src="/icons/unknown.gif" alt="Un par de l�neas describiendo la lista"></TD>
 </TR>

 <TR>
   <TD COLSPAN=2 ALIGN="center">
    <TABLE>
     <TR>
      <TD BGCOLOR="--LIGHT_COLOR--">
<INPUT TYPE="submit" NAME="action_create_list" VALUE="Enviar su petici�n de creaci�n de lista">
      </TD>
     </TR></TABLE>
</TD></TR>
</TABLE>



</FORM>




