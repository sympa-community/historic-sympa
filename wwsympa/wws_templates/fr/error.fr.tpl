<!-- RCS Identication ; $Revision$ ; $Date$ -->

[FOREACH error IN errors]

[IF error->msg=unknown_action]
[error->action] : cette action est incorrecte

[ELSIF error->msg=unknown_list]
[error->list] : cette liste est inconnue

[ELSIF error->msg=already_login]
Vous �tes d�j� connect� avec l'adresse [error->email]

[ELSIF error->msg=no_email]
Vous devez fournir votre adresse e-mail

[ELSIF error->msg=incorrect_email]
L'adresse "[error->email]" est incorrecte

[ELSIF error->msg=incorrect_listname]
"[error->listname]" : nom de liste incorrect

[ELSIF error->msg=no_passwd]
Vous devez fournir votre mot de passe

[ELSIF error->msg=user_not_found]
"[error->email]" : utilisateur non reconnu

[ELSIF error->msg=user_not_found]
"[error->email]" n'est pas un abonn�

[ELSIF error->msg=passwd_not_found]
Aucun mot de passe pour l'utilisateur "[error->email]"

[ELSIF error->msg=incorrect_passwd]
Mot de passe saisi incorrect

[ELSIF error->msg=uncomplete_passwd]
Mot de passe saisi incomplet

[ELSIF error->msg=no_user]
Vous devez vous identifier

[ELSIF error->msg=may_not]
[error->action] : vous n'�tes pas autoris� � effectuer cette action
[IF ! user->email]
<BR>identifiez-vous (Login)
[ENDIF]

[ELSIF error->msg=no_subscriber]
La liste ne comporte aucun abonn�

[ELSIF error->msg=no_page]
Pas de page [error->page]

[ELSIF error->msg=no_filter]
Aucun filtre sp�cifi�

[ELSIF error->msg=file_not_editable]
[error->file] : fichier non �ditable

[ELSIF error->msg=already_subscriber]
Vous �tes d�j� abonn� � la liste [error->list] 

[ELSIF error->msg=user_already_subscriber]
[error->email] est d�j� abonn� � la liste [error->list] 

[ELSIF error->msg=failed]
[error->action] : l'op�ration a �chou�

[ELSIF error->msg=not_subscriber]
[IF error->email]
  Pas abonn� : [error->email]
[ELSE]
Vous n'�tes pas abonn� � la liste [error->list]
[ENDIF]

[ELSIF error->msg=diff_passwd]
Les 2 mots de passe sont diff�rents

[ELSIF error->msg=missing_arg]
[error->argument] : param�tre manquant

[ELSIF error->msg=no_bounce]
Aucun bounce pour l'utilisateur [error->email]

[ELSIF error->msg=update_privilege_bypassed]
Vous avez �dit� un param�tre interdit : [error->pname]

[ELSIF error->msg=config_changed]
Le fichier de configuration a �t� modifi� par [error->email]. Impossible d'appliquer vos modifications

[ELSIF error->msg=syntax_errors]
Erreurs de syntaxe des param�tres suivants : [error->params]

[ELSIF error->msg=no_such_document]
[error->path] : document inexistant

[ELSIF error->msg=no_such_file]
[error->path] : fichier inexistant

[ELSIF error->msg=empty_document] 
Impossible de lire [error->path] : document vide

[ELSIF error->msg=no_description]
Aucune description sp�cifi�e

[ELSIF error->msg=no_content]
Echec : votre zone d'�dition est vide

[ELSIF error->msg=no_name]
Aucun nom sp�cifi�

[ELSIF error->msg=incorrect_name]
[error->name] : nom incorrect

[ELSIF error->msg = index_html]
Vous n'�tes pas autoris� � d�poser un fichier INDEX.HTML dans [error->dir]

[ELSIF error->msg=synchro_failed]
Les donn�es ont chang� sur le disque. Impossible d'appliquer vos modifications

[ELSIF error->msg=cannot_overwrite] 
Impossible d'�craser le fichier [error->path] : [error->reason]

[ELSIF error->msg=cannot_upload] 
Impossible de d�poser le fichier [error->path] : [error->reason]

[ELSIF error->msg=cannot_create_dir] 
Impossible de cr�er le r�pertoire [error->path] : [error->reason]

[ELSIF error->msg=full_directory]
Echec : le r�pertoire [error->directory] n'est pas vide

[ELSIF error->msg=init_passwd]
Vous n'avez pas d�fini de mot de passe, demandez un rappel du mot de passe initial

[ELSIF error->msg=change_email_failed]
Changement d'adresse e-mail impossible dans la liste [error->list]

[ELSIF error->msg=change_email_failed_because_subscribe_not_allowed]
Changement d'adresse e-mail impossible dans la liste [error->list]
parce que l'abonnement avec la nouvelle adresse n'est pas autoris�.

[ELSIF error->msg=change_email_failed_because_unsubscribe_not_allowed]
Changement d'adresse e-mail impossible dans la liste [error->list]
parce que le d�sabonnement n'est pas autoris�.

[ELSIF error->msg=shared_full]
Le quota d'espace disque est d�pass�.

[ELSIF error->msg=ldap_user]
Votre mot de passe est d�fini dans un annuaire LDAP, Sympa ne peut donc pas vous le rapeller

[ELSE]
[error->msg]
[ENDIF]

<BR>

[END]
