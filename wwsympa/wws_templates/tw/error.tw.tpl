<!-- RCS Identication ; $Revision$ ; $Date$ -->

[FOREACH error IN errors]

[IF error->msg=unknown_action]
[error->action] : �����ާ@

[ELSIF error->msg=unknown_list]
[error->list] : ���� Mailing List 

[ELSIF error->msg=already_login]
�z�w�g�H [error->email]  Login 

[ELSIF error->msg=no_email]
�п�J�z���q�l�l��a�}

[ELSIF error->msg=incorrect_email]
�a�}��[error->email]���O���~��

[ELSIF error->msg=incorrect_listname]
��[error->listname]��: ���~�� Mailing List �W

[ELSIF error->msg=no_passwd]
�п�J�z���K�X

[ELSIF error->msg=user_not_found]
��[error->email]��: �����Τ�

[ELSIF error->msg=user_not_found]
��[error->email]�����O�q�\��

[ELSIF error->msg=passwd_not_found]
�Τᡧ[error->email]���S���K�X

[ELSIF error->msg=incorrect_passwd]
��J���K�X�����T

[ELSIF error->msg=uncomplete_passwd]
��J���K�X������

[ELSIF error->msg=no_user]
�z�ݭn�� Login 

[ELSIF error->msg=may_not]
[error->action]: �z���Q���\�i��o�Ӿާ@
[IF ! user->email]
<BR>�z�ݭn�� Login 
[ENDIF]

[ELSIF error->msg=no_subscriber]
 Mailing List �S���q�\��

[ELSIF error->msg=no_bounce]
 Mailing List �S���Q�h�H���q�\��

[ELSIF error->msg=no_page]
�S���� [error->page]

[ELSIF error->msg=no_filter]
�ʤֹL�o

[ELSIF error->msg=file_not_editable]
[error->file]: ��󤣥i�s��

[ELSIF error->msg=already_subscriber]
�z�w�g�q�\�F Mailing List  [error->list]

[ELSIF error->msg=user_already_subscriber]
[error->email] �w�g�q�\�F Mailing List  [error->list] 

[ELSIF error->msg=failed_add]
�s�W�ϥΪ� [error->user] ����

[ELSIF error->msg=failed]
[error->action]: �ާ@����

[ELSIF error->msg=not_subscriber]
[IF error->email]
  �ëD�q�\��: [error->email]
[ELSE]
�z���O Mailing List  [error->list] ���q�\��
[ENDIF]

[ELSIF error->msg=diff_passwd]
��ӱK�X���@�P

[ELSIF error->msg=missing_arg]
�ʤְѼ� [error->argument]

[ELSIF error->msg=no_bounce]
�Τ� [error->email] �S���h�H

[ELSIF error->msg=update_privilege_bypassed]
�z�b�S���v�������p�U�ק�F�@�ӰѼ�: [error->pname]

[ELSIF error->msg=config_changed]
�]�w���w�g�Q [error->email] �ק�C�L�k���αz���ק�

[ELSIF error->msg=syntax_errors]
�U�C�Ѽƻy�k���~: [error->params]

[ELSIF error->msg=no_such_document]
[error->path]: �S�������Υؿ�

[ELSIF error->msg=no_such_file]
[error->path] : �S�������

[ELSIF error->msg=empty_document] 
�L�kŪ�� [error->path] : �Ū�����

[ELSIF error->msg=no_description] 
�S�����w�y�z

[ELSIF error->msg=no_content]
���~: �z���Ѫ����e�O�Ū�

[ELSIF error->msg=no_name]
�S�����w�W�r

[ELSIF error->msg=incorrect_name]
[error->name]: �����T���W�r

[ELSIF error->msg = index_html]
�z�S���Q���v�W�Ǥ@�� INDEX.HTML �� [error->dir] 

[ELSIF error->msg=synchro_failed]
�ϽL�ƾڤw�g���ܡC�L�k���αz���ק�

[ELSIF error->msg=cannot_overwrite] 
�L�k�л\��� [error->path] : [error->reason]

[ELSIF error->msg=cannot_upload] 
�L�k�W�Ǥ�� [error->path] : [error->reason]

[ELSIF error->msg=cannot_create_dir] 
�L�k�إߥؿ� [error->path] : [error->reason]

[ELSIF error->msg=full_directory]
����: [error->directory] ������

[ELSIF error->msg=init_passwd]
�z�å�����K�X, �Эn�D�@������K�X������
 
[ELSIF error->msg=change_email_failed]
�L�k��� [error->list] �� Email 

[ELSIF error->msg=change_email_failed_because_subscribe_not_allowed]
�L�k��s�׾� '[error->list]' ���q�\��},
�]���w�T��H�s����}�q�\.

[ELSIF error->msg=change_email_failed_because_unsubscribe_not_allowed]
�L�k��s�׾� '[error->list]' ���q�\��},
�]���w�T������q�\.

[ELSE]
[error->msg]
[ENDIF]

<BR>
[END]
