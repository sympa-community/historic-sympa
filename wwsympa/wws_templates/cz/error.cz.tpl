<!-- RCS Identication ; $Revision$ ; $Date$ -->

[FOREACH error IN errors]

[IF error->msg=unknown_action]
[error->action] : nezn�m� akce

[ELSIF error->msg=unknown_list]
[error->list] : nezn�m� konference

[ELSIF error->msg=already_login]
Jste ji� p�ihl�en jako [error->email]

[ELSIF error->msg=no_email]
Pros�m poskytn�te Va�i emailovou adresu

[ELSIF error->msg=incorrect_email]
Adresa "[error->email]" je nespr�vn�

[ELSIF error->msg=incorrect_listname]
"[error->listname]" : �patn� jm�no konference

[ELSIF error->msg=no_passwd]
Pros�m poskytn�te Va�e heslo

[ELSIF error->msg=user_not_found]
"[error->email]" : nezn�m� u�ivatel

[ELSIF error->msg=passwd_not_found]
U�ivatel "[error->email]" nem� heslo

[ELSIF error->msg=incorrect_passwd]
Poskytnut� heslo je nespr�vn�

[ELSIF error->msg=incomplete_passwd]
Poskytnut� heslo je nekompletn�

[ELSIF error->msg=no_user]
Mus�te se p�ihl�sit

[ELSIF error->msg=may_not]
[error->action] : na tuto akci nem�te opr�vn�n�
[IF ! user->email]
<BR>mus�te se p�ihl�sit
[ENDIF]

[ELSIF error->msg=no_subscriber]
Konference nem� ��dn� �leny

[ELSIF error->msg=no_bounce]
Konference neobsahuje chybn� adresy

[ELSIF error->msg=no_page]
Strana [error->page] neexistuje

[ELSIF error->msg=no_filter]
Chyb�j�c� filtr

[ELSIF error->msg=file_not_editable]
[error->file] : soubor se ned� upravovat

[ELSIF error->msg=already_subscriber]
V konferenci [error->list] jste ji� �lenem

[ELSIF error->msg=user_already_subscriber]
[error->email] je ji� �lenem konference [error->list] 

[ELSIF error->msg=failed_add]
Chyba p�i p�id�v�n� u�ivatele [error->user]

[ELSIF error->msg=failed]
[error->action]: akce selhala

[ELSIF error->msg=not_subscriber]
[IF error->email]
  Nejste p�ihl�en: [error->email]
[ELSE]
Nejste �lenem konference [error->list]
[ENDIF]

[ELSIF error->msg=diff_passwd]
Hesla nejsou stejn�

[ELSIF error->msg=missing_arg]
Chyb�j�c� parametr [error->argument]

[ELSIF error->msg=no_bounce]
Pro u�ivatele [error->email] nejsou vr�cen� zpr�vy

[ELSIF error->msg=update_privilege_bypassed]
Zm�nil jste parametr bez opr�vn�n�: [error->pname]

[ELSIF error->msg=config_changed]
[error->email] zm�nil konfigura�n� soubor. Va�e zm�ny nelze pou��t

[ELSIF error->msg=syntax_errors]
Syntaktick� chyba s n�sledujc�mi parametry : [error->params]

[ELSIF error->msg=no_such_document]
[error->path] : Cesta nenalezena

[ELSIF error->msg=no_such_file]
[error->path] : soubor neexistuje

[ELSIF error->msg=empty_document] 
Nelze ��st soubor [error->path] : pr�zdn� dokument

[ELSIF error->msg=no_description] 
Popis nespecifikov�n

[ELSIF error->msg=no_content]
Chyba : obsah je pr�zdn�

[ELSIF error->msg=no_name]
Z�dn� jm�no nespecifikov�no 

[ELSIF error->msg=incorrect_name]
[error->name] : nespr�vn� jm�no 

[ELSIF error->msg = index_html]
Nem�te opr�vn�n� nahr�t INDEX.HTML do adres��e [error->dir] 

[ELSIF error->msg=synchro_failed]
Data zm�n�na na disku. Va�e zm�ny nelze pou��t 

[ELSIF error->msg=cannot_overwrite] 
Nelze p�epsat soubor [error->path] : [error->reason]

[ELSIF error->msg=cannot_upload] 
Nelze nahr�t soubor [error->path] : [error->reason]

[ELSIF error->msg=cannot_create_dir] 
Nelze vytvo�it adres�� [error->path] : [error->reason]

[ELSIF error->msg=full_directory]
Chyba : Adres�� [error->directory] nen� pr�zdn�

[ELSIF error->msg=init_passwd]
Nezvolil jste si heslo, nechte si jej poslat 

[ELSIF error->msg=change_email_failed]
Nelze zm�nit emailovou adresu pro konferenci [error->list]

[ELSIF error->msg=change_email_failed_because_subscribe_not_allowed]
Nelze zm�nit Va�i adresu v konferenci '[error->list]', proto�e nen� dovoleno
p�ihl�sit Va�i novou adresu.

[ELSIF error->msg=change_email_failed_because_unsubscribe_not_allowed]
Nelze zm�nit Va�i adresu v konferenci '[error->list]', proto�e V�m nen� dovoleno
odhl�sit se.

[ELSIF error->msg=shared_full]
The document repository exceed disk quota.

[ELSIF error->msg=ldap_user]
Your password is stored in an LDAP directory, therefore Sympa cannot post you a reminder

[ELSIF error->msg=select_month]
Please select archive months

[ELSE]
[error->msg]
[ENDIF]

<BR>
[END]
