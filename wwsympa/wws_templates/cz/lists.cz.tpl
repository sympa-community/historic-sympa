<!-- RCS Identication ; $Revision$ ; $Date$ -->

[IF action=search_list]
  nalezeno [occurrence] v�skyt�<BR><BR>
[ELSIF action=search_user]
  <B>[email]</B> je p�ihl�en v n�sleduj�c�ch konferenc�ch
[ENDIF]

<TABLE BORDER="0" WIDTH="100%">
   [FOREACH l IN which]
     <TR>
     [IF l->admin]
       <TD>
       [PARSE '--ETCBINDIR--/wws_templates/button_header.tpl']
       <TD BGCOLOR="[light_color]" ALIGN="center" VALIGN="top">
             <FONT COLOR="[selected_color]" SIZE="-1">
              <A HREF="[path_cgi]/admin/[l->NAME]" ><b>Admin</b></A>
         </FONT>
       </TD>
     [PARSE '--ETCBINDIR--/wws_templates/button_footer.tpl']

</TD>
     [ELSE]
       <TD>&nbsp;</TD>
     [ENDIF] 
     <TD WIDTH="100%" ROWSPAN="2">
     <A HREF="[path_cgi]/info/[l->NAME]" ><B>[hidden_head][l->NAME][hidden_at][l->host][hidden_end]</B></A>
     <BR>
     [l->subject]
     </TD></TR>
     <TR><TD>&nbsp;</TD></TR>
   [END]
</TABLE>

<BR>

[IF action=which]
[IF ! which]
&nbsp;&nbsp;<FONT COLOR="[dark_color]">��dn� p�ihl�en� z adresy <B>[user->email]</B>!</FONT>
<BR>
[ENDIF]

[IF unique <> 1]
<TABLE>
&nbsp;&nbsp;<FONT COLOR="[dark_color]">P�ehled p�ihl�en� z n�sleduj�c�ch adres</FONT><BR>
<BR><BR>

 <TR> 
    <FORM METHOD=POST ACTION="[path_cgi]">
     
[FOREACH email IN alt_emails]
   <INPUT NAME="email"  TYPE=hidden VALUE="[email->NAME]">
   &nbsp;&nbsp;<A HREF="[path_cgi]/change_identity/[email->NAME]/which">[email->NAME]</A> 
    <BR>
    [END]  
    </FORM>
  </TR>
</TABLE>

<BR> 

<TABLE>
<TR>
&nbsp;&nbsp;<FONT COLOR="[dark_color]">Sjednotit p�ihl�en� na adresu <B>[user->email]</B></FONT><BR> 
&nbsp;&nbsp;<FONT COLOR="[dark_color]">To znamen�, �e pro nastaven� v Symp� pou�ijete pouze jednu adresu</FONT>

<TR>
<TD>
    <FORM ACTION="[path_cgi]" METHOD=POST>
  
&nbsp;&nbsp;<INPUT TYPE="submit" NAME="action_unify_email" VALUE="Potvrdit"></FONT>
    </FORM>
</TD>
</TR>
<BR>

</TABLE>
[ENDIF]
[ENDIF]
