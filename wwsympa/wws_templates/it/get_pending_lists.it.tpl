
<FORM ACTION="[path_cgi]" METHOD=POST>

<HR  WIDTH=90%>

<P>
<TABLE>
 <TR>
   <TD Colspan=3 bgcolor="--LIGHT_COLOR--"><B>Liste in attesa</B></TD>
 </TR>
 <TR bgcolor="--LIGHT_COLOR--">
   <TD><B>nome della lista</B></TD>
   <TD><B>soggetto</B></TD>
   <TD><B>Richiesto da</B></TD>
 </TR>

[FOREACH list IN pending]
<TR>
<TD><A HREF="[path_cgi]/set_pending_list_request/[list->NAME]">[list->NAME]</A></TD></TD>
<TD>[list->subject]</TD>
<TD>[list->by]</TD>
</TR>
[END]
</TABLE>




