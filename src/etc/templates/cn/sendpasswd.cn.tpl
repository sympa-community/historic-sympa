From: [conf->sympa]
Reply-to: [conf->request]
To: [newuser->email]
Subject: ���� [wwsconf->title] ��������

[IF action=subrequest]
���������ʵݱ� [list]��

Ҫȷ�����Ķ��ģ�����Ҫʹ�����µĿ���

	����: [newuser->password]

[ELSIF action=sigrequest]
������ȡ�������ʵݱ� [list]��

Ҫȡ�����ģ�����Ҫʹ�����µĿ���

	����: [newuser->password]

[ELSE]
Ҫ���������˵Ļ�����������Ҫ��¼

     �����ʼ���ַ: [newuser->email]
     �� �� �� �� : [newuser->password]

�޸����Ŀ���
[base_url][path_cgi]/choosepasswd/[newuser->escaped_email]/[newuser->password]
[ENDIF]


[wwsconf->title]: [base_url][path_cgi] 

Sympa �İ���: [base_url][path_cgi]/help

