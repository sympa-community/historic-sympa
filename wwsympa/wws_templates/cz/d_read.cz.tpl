<!-- RCS Identication ; $Revision$ ; $Date$ -->

[IF file]
  [INCLUDE file]
[ELSE]

  [IF path]  
     <h2><B><IMG SRC="[icons_url]/folder.open.png"> [path] </B> </h2> 
    <A HREF="[path_cgi]/d_editfile/[list]/[escaped_path]">upravit</A> | 
    <A HREF="[path_cgi]/d_delete/[list]/[escaped_path]" onClick="request_confirm_link('[path_cgi]/d_delete/[list]/[escaped_path]', 'Chcete opravdu smazat [path] ?'); return false;">smazat</A> |
    <A HREF="[path_cgi]/d_control/[list]/[escaped_path]">p��stup</A><BR>

    Vlastn�k : [doc_owner] <BR>
    Posledn� zm�na : [doc_date] <BR>
    [IF doc_title]
    Popis : [doc_title] <BR><BR>
    [ENDIF]
    <font size=+1> <A HREF="[path_cgi]/d_read/[list]/[escaped_father]"> <IMG ALIGN="bottom"  src="[father_icon]" BORDER="0"> O �rove� v��</A></font>
    <BR>  
  [ELSE]
    <h2> <B> V�pis sd�len�ho adres��e </B> </h2> 
  [ENDIF]
   
  <TABLE width=100%>
  <TR BGCOLOR="[dark_color]">
   
  <th><TABLE width=100%><TR><TD ALIGN="left"><font color="[bg_color]">Dokument</font></TD>
  [IF  order_by<>order_by_doc]  
    <TD ALIGN="right">
    <form method="post" ACTION="[path_cgi]">  
    <INPUT ALIGN="top"  type="image" src="[sort_icon]" WIDTH=15 HEIGHT=15 name="Set��dit podle jm�na">
    <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
    <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
    <INPUT TYPE="hidden" NAME="action" VALUE="d_read">
    <INPUT TYPE="hidden" NAME="order" VALUE="order_by_doc">
    </form>
    </TD>
  [ENDIF]	
  </TR></TABLE>
  </th>
  
  <th><TABLE width=100%><TR><TD ALIGN="left"><font color="[bg_color]">Autor</font></TD>
  [IF  order_by<>order_by_author]  
    <TD ALIGN="right">
    <form method="post" ACTION="[path_cgi]">  
    <INPUT ALIGN="top"  type="image" src="[sort_icon]" WIDTH=15 HEIGHT=15 name="Set��dit podle autora">
    <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
    <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
    <INPUT TYPE="hidden" NAME="action" VALUE="d_read">
    <INPUT TYPE="hidden" NAME="order" VALUE="order_by_author">
    </form>	
    </TD>
  [ENDIF]
  </TR></TABLE>
  </th> 

  <th><TABLE width=100%><TR><TD ALIGN="left"><font color="[bg_color]">Velikost (Kb)</font></TD>
  [IF order_by<>order_by_size] 
    <TD ALIGN="right">
    <form method="post" ACTION="[path_cgi]">
    <INPUT ALIGN="top"  type="image" src="[sort_icon]" WIDTH=15 HEIGHT=15 name="Set��dit podle velikosti">
    <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
    <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
    <INPUT TYPE="hidden" NAME="action" VALUE="d_read">
    <INPUT TYPE="hidden" NAME="order" VALUE="order_by_size">
    </form>
    </TD>
  [ENDIF]
  </TR></TABLE>   
  </th> 

  <th><TABLE width=100%><TR><TD ALIGN="left"><font color="[bg_color]">Posledn� zm�na</font></TD>
  [IF order_by<>order_by_date]
    <TD ALIGN="right">
    <form method="post" ACTION="[path_cgi]">
    <INPUT ALIGN="top"  type="image" src="[sort_icon]" WIDTH=15 HEIGHT=15 name="Set��dit podle data">
    <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
    <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
    <INPUT TYPE="hidden" NAME="action" VALUE="d_read">
    <INPUT TYPE="hidden" NAME="order" VALUE="order_by_date">
    </form>
    </TD>
  [ENDIF]
  </TR></TABLE>  
  </th> 

  <TD ALIGN="center"><font color="[bg_color]">Upravit</font></TD> 
  <TD ALIGN="center"><font color="[bg_color]">Smazat</font></TD>
  <TD ALIGN="center"><font color="[bg_color]">Opr�vn�n�</font></TD></TR>
      
  [IF empty]
    <TR BGCOLOR="[light_color]" VALIGN="top">
    <TD COLSPAN=8 ALIGN="center"> Pr�zdn� adres�� </TD>
    </TR>
  [ELSE]   
    [IF sort_subdirs]
      [FOREACH s IN sort_subdirs] 
        <TR BGCOLOR="[light_color]">        
	<TD NOWRAP> <A HREF="[path_cgi]/d_read/[list]/[escaped_path][s->escaped_doc]/"> 
	<IMG ALIGN=bottom BORDER=0 SRC="[s->icon]" ALT="[s->escaped_title]"> [s->doc]</A></TD>
	<TD>
	[IF s->author_known] 
	  [s->author_mailto]
        [ELSE]
	   Nezn�m� 
	[ENDIF]
	</TD>	    
	<TD>&nbsp;</TD>
	<TD NOWRAP> [s->date] </TD>
	
	[IF s->edit]

	<TD><center>
	<font size=-1>
	<A HREF="[path_cgi]/d_editfile/[list]/[escaped_path][s->escaped_doc]">upravit</A>
	</font>
	</center></TD>

	  <TD><center>
	  <FONT size=-1>
	  <A HREF="[path_cgi]/d_delete/[list]/[escaped_path][s->escaped_doc]" onClick="request_confirm_link('[path_cgi]/d_delete/[list]/[escaped_path][s->escaped_doc]', 'Opravdu chcete smazat [path][s->doc] ?'); return false;">smazat</A>
	  </FONT>
	  </center></TD>
	[ELSE]
	  <TD>&nbsp; </TD>
	  <TD>&nbsp; </TD>
	[ENDIF]
	
	[IF s->control]
	  <TD>
	  <center>
	  <FONT size=-1>
	  <A HREF="[path_cgi]/d_control/[list]/[escaped_path][s->escaped_doc]">opr�vn�n�</A>
	  </font>
	  </center>
	  </TD>	 
	[ELSE]
	  <TD>&nbsp; </TD>
	[ENDIF]
      </TR>
      [END] 
    [ENDIF]

    [IF sort_files]
      [FOREACH f IN sort_files]
        <TR BGCOLOR="[light_color]"> 
        <TD>&nbsp;
        [IF f->html]
	  <A HREF="[path_cgi]/d_read/[list]/[escaped_path][f->escaped_doc]" TARGET="html_window">
	  <IMG ALIGN=bottom BORDER=0 SRC="[f->icon]" ALT="[f->escaped_title]"> [f->doc] </A>
	[ELSIF f->url]
	  <A HREF="[f->url]" TARGET="html_window">
	  <IMG ALIGN=bottom BORDER=0 SRC="[f->icon]" ALT="[f->escaped_title]"> [f->anchor] </A>
	[ELSE]
	  <A HREF="[path_cgi]/d_read/[list]/[escaped_path][f->escaped_doc]">
	  <IMG ALIGN=bottom BORDER=0 SRC="[f->icon]" ALT="[f->escaped_title]"> [f->doc] </A>
        [ENDIF] 
	</TD>  
	 
	<TD> 
	[IF f->author_known]
	   [f->author_mailto]
	[ELSE]
          Nezn�m�  
        [ENDIF]
	</TD>
	 
	<TD NOWRAP>&nbsp;
	[IF !f->url]
	[f->size] 
	[ENDIF]
	</TD>
	<TD NOWRAP> [f->date] </TD>
	 
	[IF f->edit]
	<TD>
	<center>
	<font size=-1>
	<A HREF="[path_cgi]/d_editfile/[list]/[escaped_path][f->escaped_doc]">upravit</A>
	</font>
	</center>

	</TD>
	<TD>
	<center>
	<FONT size=-1>
	<A HREF="[path_cgi]/d_delete/[list]/[escaped_path][f->escaped_doc]" onClick="request_confirm_link('[path_cgi]/d_delete/[list]/[escaped_path][f->escaped_doc]', 'Opravdu chcete smazat [path][s->doc] ([f->size] Kb) ?'); return false;">smazat</A>
	</FONT>
	</center>
	</TD>
	[ELSE]
	  <TD>&nbsp; </TD> <TD>&nbsp; </TD>
	[ENDIF]
		 
	[IF f->control]
	  <TD> <center>
	  <font size=-1>
	  <A HREF="[path_cgi]/d_control/[list]/[escaped_path][f->escaped_doc]">opr�vn�n�</A>
	  </font>
	  </center></TD>
	[ELSE]
	<TD>&nbsp; </TD>
	[ENDIF]
	</TR>
      [END] 
    [ENDIF]
  [ENDIF]
  </TABLE>	        
 
  <HR> 
<TABLE CELLSPACING=20>
   
   [IF path]
         
   [IF may_edit]
    <TR>
    <form method="post" ACTION="[path_cgi]">
    <TD ALIGN="right" VALIGN="bottom">
    [IF path]
      <B> Vytvo�it nov� adres�� v adres��i [path]</B> <BR>
    [ELSE]
      <B> Vytvo�it nov� adres�� ve sd�len�m adres��i</B> <BR>
    [ENDIF]
    <input MAXLENGTH=30 type="text" name="name_doc">
    </TD>
      
    <TD ALIGN="left" VALIGN="bottom">
    <input type="submit" value="Vytvo�it nov� adres��" name="action_d_create_dir">
    <INPUT TYPE="hidden" NAME="previous_action" VALUE="d_read">
    <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
    <INPUT TYPE="hidden" NAME="path" VALUE="[path]">     
    <INPUT TYPE="hidden" NAME="type" VALUE="directory">
    <INPUT TYPE="hidden" NAME="action" VALUE="d_create_dir">
    </TD>
    </form>
    </TR>
   
      <TR>   
      <form method="post" ACTION="[path_cgi]">
    <TD ALIGN="right" VALIGN="bottom">
      <B> Vytvo�it nov� soubor</B> <BR>
    <input MAXLENGTH=30 type="text" name="name_doc">
      </TD>
     
      <TD ALIGN="left" VALIGN="bottom">
    <input type="submit" value="Vytvo�it nov� soubor" name="action_d_create_dir">
    <INPUT TYPE="hidden" NAME="previous_action" VALUE="d_read">
      <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
      <INPUT TYPE="hidden" NAME="path" VALUE="[path]">     
    <INPUT TYPE="hidden" NAME="type" VALUE="file">
    <INPUT TYPE="hidden" NAME="action" VALUE="d_create_dir">
      </TD>
      </form>
      </TR>

    <TR>
    <FORM METHOD="POST" ACTION="[path_cgi]">
    <TD ALIGN="right" VALIGN="center">
    <B>P�idat z�lo�ku</B><BR>
    title <input MAXLENGTH=100 SIZE="20" type="text" name="name_doc"><BR>
    URL <input MAXLENGTH=100 SIZE="25" type="text" name="url">

    </TD>

    <TD ALIGN="left" VALIGN="bottom">
    <input type="submit" value="P�idat" name="action_d_savefile">
    <INPUT TYPE="hidden" NAME="previous_action" VALUE="d_read">
    <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
    <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
    <INPUT TYPE="hidden" NAME="action" VALUE="d_savefile">
    </TD>
    </FORM>
    </TR>


   <TR>
   <form method="post" ACTION="[path_cgi]" ENCTYPE="multipart/form-data">
   <TD ALIGN="right" VALIGN="bottom">
   [IF path]
     <B> Nahr�t soubor do adres��e [path]</B><BR>
   [ELSE]
     <B> Nahr�t soubor do sd�len�ho adres��e</B><BR>
   [ENDIF]
   <input type="file" name="uploaded_file">
   </TD>

   <TD ALIGN="left" VALIGN="bottom">
   <input type="submit" value="Publikovat" name="action_d_upload">
   <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
   <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
   <TD>
   </form> 
   </TR>
   [ENDIF]
</TABLE>
[ENDIF]
   




