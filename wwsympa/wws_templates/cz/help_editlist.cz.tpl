<!-- RCS Identication ; $Revision$ ; $Date$ -->

[FOREACH p IN param]
  <A NAME="[p->NAME]"></a>
  <B>[p->title]</B> ([p->NAME]):
  <DL>
    <DD>
      [IF p->NAME=add]
        Opr�vn�n� pro p�id�n� (p��kaz ADD) �lena do konference
      [ELSIF p->NAME=anonymous_sender]
        Pro skryt� emailov� adresy odes�latele p�ed distribuc� zpr�vy. Tato adresa
        je nahrazena definovanou adresou.
      [ELSIF p->NAME=archive]
        Opr�vn�n� ��st arch�vy zpr�v a frekvenci archivov�n�
      [ELSIF p->NAME=available_user_options]
        Parametr available_user_options za��n� odstavec, kter� definuje mo�n�
        volby pro �leny konference.<BR><BR>
        <UL>
          <LI>reception <i>modelist</i> (V�choz� hodnota: reception mail,notice,digest,summary,nomail)<BR><BR>
              <i>modelist</i> je seznam re�im� (mail, notice, digest, summary, nomail), odd�len�ch ��rkou.
              Pouze tyto re�imy budou dovoleny �len�m konference. Pokud m� �len
              re�im  p��jmu zpr�v, kter� nen� na seznamu, Sympa pou�ije re�im
              definovan� v odstavci default_user_options.
        </UL>
      [ELSIF p->NAME=bounce]
        Tento odstavec definuje parametry pro spr�vu vr�cen�ch zpr�v:<BR><BR>
        <UL>
          <LI>warn_rate (V�choz� hodnota: parametr robotu bounce_warn_rate)<BR><BR>
              Spr�vce konference dostane varov�n� kdykoliv je n�jak� zpr�va rozesl�na a po�et vr�cen�ch
              zpr�v (v procentech) p�ekro�� tuto hodnotu.
          <LI>halt_rate (V�choz� hodnota: parametr robotu bounce_halt_rate)<BR><BR>
              ZAT�M NEPOU�ITO. Pokud hodnota bounce rate dos�hne stavu halt_rate, zpr�vy do konference
              se p�estanou odes�lat, t.j. budou zachov�ny pro n�sledn� moderov�n�.
           <LI>expire_bounce_task (V�choz� hodnota: daily)<BR><BR>
               Jm�no �ablony �kolu kter� se pou�ije pro odstran�n� star�ch vr�cen�ch zpr�v.
               Je to u�ite�n� pro odstran�n� vr�cen�ch zpr�v z ur�it� adresy �lena pokud jsou
               jin� zpr�vy doru�ov�ny bez probl�m�. V tomto p��pad� je adresa �lena v po��dku.
               �kol je aktivn� pokud b�� proces task_manager.pl.
         </UL>

      [ELSIF p->NAME=bouncers_level1]
        Odstavce Bouncers_level1 definuj� automatick� chov�n� spr�vy vr�cen�ch zpr�v.<BR>
        �rove� 1 je nejni��� �rove� vracej�c�ch se adres<BR><BR>

        <UL>
          <LI>rate (V�choz� hodnota: 45)<BR><BR>
              Ka�d� u�ivatel jemu� se vrac� zpr�vy m� ur�it� sk�re (od 0 do 100).
              Tento parametr definuje doln� hranici pro ka�dou kategorii.
              Na p��klad �rove� 1 za��n� od 45 do hodnoty level_2_treshold.
          <LI> action (V�choz� hodnota: notify_bouncers)<BR><BR>
               Tento parametr definuje kter� �loha bude automaticky aplikov�na na vr�cej�c� se adresy
               �rovn� 1.
           <LI>Notification  (V�choz� hodnota: owner)<BR><BR>
               Kdy� se spust� automatick� �loha, za�le se upozorn�n� spr�vci konference nebo serveru.
        </UL>

      [ELSIF p->NAME=bouncers_level2]
        Odstavce Bouncers_levelX definuj� automatick� chov�n� spr�vy vr�cen�ch zpr�v.<BR>
        �rove� 2 je nejvy��� �rove� vracej�c�ch se adres<BR><BR>

        <UL>
          <LI>rate (V�choz� hodnota: 80)<BR><BR>
              Ka�d� u�ivatel jemu� se vrac� zpr�vy m� ur�it� sk�re (od 0 do 100).
              Tento parametr definuje doln� hranici pro ka�dou kategorii.
              Na p��klad �rove� 2 je od 80 do 100.
          <LI> action (V�choz� hodnota: notify_bouncers)<BR><BR>
               Tento parametr definuje kter� �loha bude automaticky aplikov�na na vr�cej�c� se adresy
               �rovn� 2.
           <LI>Notification  (V�choz� hodnota: owner)<BR><BR>
               Kdy� se spust� automatick� �loha, za�le se upozorn�n� spr�vci konference nebo serveru.
        </UL>
      [ELSIF p->NAME=cookie]
        Tento parametr je d�v�rn� polo�ka pro generov�n� autentiza�n�ch kl��� pro
        pro administrativn� p��kazy (ADD, DELETE, atd.). Tento parametr by m�l z�stat utajen, i pro spr�vce konference.
        Tato hodnota je aplikov�na na v�echny spr�vce konferenc� a br�na v potaz pouze pokud m� spr�vce parametr auth.
      [ELSIF p->NAME=custom_header]
        Tento parametr je voliteln�. Hlavi�ky zde definovan� budou p�id�ny ke v�em zpr�v�m
        rozeslan�m do konference. Od verze Sympa 1.2.2je mo�n� vlo�it do konfigura�n�ho souboru v�ce ��dk� 
        s vlastn�mi hlavi�kami najednou.
      [ELSIF p->NAME=custom_subject]
        Tento parametr je voliteln�. Definuje �et�zec kter� je p�id�n do p�edm�tu rozes�lan�ch zpr�v.
        Tento �et�zec bude obklopen znaky [].
      [ELSIF p->NAME=default_user_options]
        Parametr default_user_options za��n� odstavec, kter� definuje v�choz� profil pro �leny konference.<BR><BR>
        <UL>
          <LI>reception notice | digest | summary | nomail | mail<BR><BR>Zp�sob p�ij�m�n� zpr�v.
          <LI>visibility conceal | noconceal<BR><BR>Viditelnost �lena ve v�stupu p��kazu REVIEW.
        </UL>
      [ELSIF p->NAME=del]
        Tento parametr definuje kdo je opr�vn�n pou��t p��kaz DEL.
      [ELSIF p->NAME=digest]
        Definice �e�imu digest. Pokud je tento parametr p��tomn� mohou �lenov� zvolit zp�sob p�ij�m�n�
        zpr�v ve form�tu multipart/digest. Zpr�vy jsou seskupeny dohromady a pravideln� rozesl�ny v jedn� zpr�v� podle
	�etnosti definovan� t�mto parametrem.
      [ELSIF p->NAME=editor]
		Edito�i (nebo moder�to�i) jsou zodpov�dn� za moderov�n� zpr�v. Pokud je konference moderovan�,
		zpr�vy poslan� do konference jsou nej��v poslan� editor�m, kte�� rozhodnou,
		jestli se zpr�va roze�le nebo odm�tne. <BR>
		FYI: Ur�en� editor� nenastav� konferenci jako moderovanou; mus�te zm�nit
		parametr "send".<BR>
		FYI: Pokud je konference moderovan�, prvn� editor, kter� potvrd�
		nebo odm�tne zpr�vu rozhodne za ostatn� editory. Pokud se nikdo nerozhodne,
		zprava z�stane ve front� nemoderovan�ch zpr�v.
      [ELSIF p->NAME=expire_task]
        Tento parametr ur�uje, kter� model se pou�ije pro vytvo�en� upozor�ovac�ho �kolu.
        �kol vypr�en� pravideln� kontroluje datum p�ihl�en� �len� a po�aduje po nich obnoven� jejich �lenstv�.
        Pokud je neobnov�, jsou odstran�ni.
      [ELSIF p->NAME=footer_type]
        Spr�vci konference se mohou rozhodnout p�id�vat ur�it� text na za��tek nebo na konec zpr�v rozes�lan�ch
        do konference. Tento parametr definuje zp�sob, jak�m je tento text do zpr�vy vkl�d�n.<BR><BR>
        <UL>
          <LI>footer_type mime<BR><BR>
              V�choz� hodnota. Sympa bude p�id�vat text jako novou p��lohu zpr�vy.
              Pokud je zpr�va ve form�tu multipart/alternative, nestane se nic (nebo� by to vy�adovalo
              vytv��et dal�� �rove� vkl�dan� zpr�v).
          <LI>footer_type append<BR><BR>
              Sympa bude vkl�dat text p��mo do t�la zpr�v. Ji� definovan� p��pony budou ignorov�ny.
              Text se bude vkl�dat pouze do zpr�v v prost�m form�tu bez p��loh (text/plain).
          </LI>
        </UL>
      [ELSIF p->NAME=host]
        Jm�no dom�ny konference, v�choz� hodnota je jm�no dom�ny robota, nastaven� v odpov�daj�c�m souboru
        robot.conf nebo v souboru /etc/sympa.conf.
      [ELSIF p->NAME=include_file]
        Tento parametr bude zpracov�n pouze v p��pad�, �e polo�ka user_data_source m� nastavenou hodnotu
        "include". Soubor by m�l pouze obsahovat jednou emailovou adresu na ��dek. (��dky za��naj�c� znakem
        "#" jsou ignorov�ny).
      [ELSIF p->NAME=include_ldap_2level_query]
        Tento odstaven definuje parametry pro dvoj�rov�ov� LDAP dotaz, kter� vrac� seznam �len�.
        Obvykle prvn� �rove� dotazu vrac� seznam DN a druh� �rove� dotazu p�evede DN a emailov� adresy. Tento parametr
        se pou�ije pouze pokud je parametr user_data_source nastaven na "include". Tato funkce vy�aduje
        modul Net::LDAP (perlldap).
      [ELSIF p->NAME=include_ldap_query]
        Tento odstavec definuje parametry pro LDAP dotaz, kter� vrac� seznam �len� konference.
        Tento parametr se pou�ije pouze pokud je parametr user_data_source nastaven na "include". 
        Tato funkce vy�aduje modul Net::LDAP (perlldap).
      [ELSIF p->NAME=include_list]
        Tento parametr se pou�ije pouze pokud je parametr user_data_source nastaven na "include". 
        V�ichni �lenov� dan� konference se stanou �leny t�to konference.
        M��ete zahrnout v�ce konferenc� podle pot�eby definov�n�m v�ce ��dk� include_list.
        M��ete vkl�dat libovolnou konferenci bez ohledu na zp�sob definice t� konference.
        Dejte pozor na to, abyste nevlo�ili konferenci A do konference B a potom konferenci B do konference A,
        nebo� to by zp�sobilo nekone�nou smy�ku.
      [ELSIF p->NAME=include_remote_sympa_list]
        Sympa m��e kontaktovat jinou slu�bu Sympy pomoci https protokolu a z�skat seznam �len� vzd�len� konference.
        Lze definovat v�ce konferenci najednou podle pot�eby. Dejte jenom pozor aby nevznikaly kruhov� vazby.        
        <BR><BR>
        Pro tuto operaci jedno m�sto Sympa funguje jako server, zat�mco druh� jako klient.
        Na strane serveru je nutno nastavit opr�vn�n� pro vzd�lenou Sympu. Toto se ��d� scen��em review.
      [ELSIF p->NAME=include_sql_query]
        Tento parametr se pou�ije pouze pokud je parametr user_data_source nastaven na "include" a za��n� odstavec,
        kter� definuje parametry SQL dotazu.
      [ELSIF p->NAME=lang]
        Tento parametr ur�uje v�choz� jazyk konference. Je pou�it pro v�choz� nastaven� volby jazyka u�ivatele;
        v�stupy p��kaz� Sympy jsou vyta�eny z p��slu�n�ho katalogu zpr�v.
      [ELSIF p->NAME=max_size]
        Maxim�ln� velikost zpr�vy v bajtech.
      [ELSIF p->NAME=owner]
        Vlastn�ci spravuj� �leny konference. Mohou si prohl�et seznam �len�, p�id�vat
        nebo mazat adresy ze seznamu. Pokud jste opr�vn�n�m spr�vcem konference,
        m��ete ur�it jin� vlastn�ky konference.
	Privilegovan� vlastn�ci mohou upravovat v�ce parametr� ne� jin� vlastn�ci. Pro
	konferenci m��e b�t pouze jeden prvilogovan� vlastn�k, jeho adresa se
	ned� m�nit z webu.
      [ELSIF p->NAME=priority]
        Priorita se kterou bude Sympa zpracov�van zpr�vy pro tuto konferenci. Tato �rove� priority je aplikov�na
        ve chv�li, kdy zpr�va proch�z� frontou zpr�v.
      [ELSIF p->NAME=remind]
        Teto parametr ur�uje kdo je autorizov�n pou��t p��kaz REMIND.
      [ELSIF p->NAME=remind_return_path]
        Stejn� jako parametr welcome_return_path, ale aplikov�no na upom�nac� zpr�vy.
      [ELSIF p->NAME=remind_task]
        Tento parametr ur�uje model, kter� se pou�ije pro vytvo�en� upom�nac� �lohy. Tato �loha pravideln�
        rozes�l� �len�m zpr�vu, kter� jim p�ipom�n� jejich �lenstv� v konferenci.
      [ELSIF p->NAME=reply_to_header]
        Parametr reply_to_header za��n� odstavec, kter� definuje co Sympa um�st� Sympa do
        hlavi�ky Reply-To: ve zpr�v� kterou rozes�l�.<BR><BR>
        <UL>
          <LI>value sender | list | all | other_email (V�choz� hodnota: sender)<BR><BR>
              Tento parametr ur�uje zda polo�ka Reply-To: by m�la obsahovat odes�latele (sender),
              konferenci (list), oba dva (all) nebo n�jakou jinou adresu (definovanou parametrem
              other_email).<BR><BR>
              Pozn�mka: Nen� doporu�eno m�nit tento parametr a zejm�na jej nastavovat na adresu konference.
              Ze zku�enosti se ukazuje, �e je t�m�� nevyhnuteln�, �e u�ivatel� budou v��it tomu, �e
              pos�laj� zpr�vu pouze odes�lateli, ale ode�lou ji do konference. To m��e v�st p�inejmen��m
              k trapasu, ale m��e to m�t i v�n�j�� n�sledky.<BR><BR>
          </LI>
          <LI>other_email emailova adresa<BR><BR>
              Pokud je polo�ka value nastavena na other_email, pak tento parametr ur�uje pou�itou adresu.<BR><BR>
          </LI>
          <LI>apply respect | forced (V�choz� hodnota: respect)<BR><BR>
               V�choz� hodnota je zachov�vat ji� existuj�c� polo�ku hlavi�ky ve zpr�v�ch. Pokud je nastaveno "forced", 
               hlavi�ka bude p�eps�na.
          </LI>
        </UL>
      [ELSIF p->NAME=review]
        Tento parametr ur�uje kdo m��e z�skat seznam �len�. Proto�e adresy �len� mohou b�t zneu�ity pro
        ���en� nevy��dan�ch zpr�v, je doporu�eno, abyste autorizoval pouze spr�vce nebo existuj�c� �leny.
      [ELSIF p->NAME=send]
        Tento parametr definuje kdo m��e pos�lat zpr�vy do konference. Platn� hodnoty pro tento parametr jsou
        odkazy na existuj�c� scen��e.<BR><BR>
        <UL>
          <LI>send closed<BR>uzav�ena
          <LI>send editor<BR>moderov�na, star� styl
          <LI>send editorkey<BR>Moderov�na
          <LI>send editorkeyonly<BR>Moderov�na i pro moder�tory
          <LI>send editorkeyonlyauth<BR>Moderov�na, s potvrzen�m moder�tora
          <LI>send intranet<BR>omezena na lok�ln� dom�nu
          <LI>send intranetorprivate<BR>omezena na lok�ln� dom�nu a �leny
          <LI>send newsletter<BR>Ob�n�k, omezena jen pro moder�tory
          <LI>send newsletterkeyonly<BR>Ob�n�k, omezena jen pro moder�tory po potvrzen�
          <LI>send private<BR>pouze pro �leny
          <LI>send private_smime<BR>pouze pro �leny, kontrola podpisu SMIME
          <LI>send privateandeditorkey<BR>Moderov�na, pouze pro �leny
          <LI>send privateandnomultipartoreditorkey<BR>Moderov�na, pro ne�leny nebo zpr�vy s p��lohou
          <LI>send privatekey<BR>omezena jen pro �leny s p�edchoz� MD5 autentizac�
          <LI>send privatekeyandeditorkeyonly<BR>Moderov�na, pro �leny a moder�tory
          <LI>send privateoreditorkey<BR>Soukrom�, ne�leni moderov�ni
          <LI>send privateorpublickey<BR>Soukrom�, ne�len� po potvrzen�
          <LI>send public<BR>ve�ejn� konference
          <LI>send public_nobcc<BR>ve�ejn� konference, BCC odm�tnuto (anti-spam)
          <LI>send publickey<BR>kdokoliv s p�edchoz� MD5 autentizac�
          <LI>send publicnoattachment<BR>ve�ejn�, zpr�vy s p��lohou pred�ny moder�tor�m
          <LI>send publicnomultipart<BR>ve�ejn�, zpr�vy s p��lohou jsou odm�tnuty
        </UL>
      [ELSIF p->NAME=shared_doc]
        Tento odstavec definuje pr�va pro �ten� a �pravy pro adres�� se sd�len�mi dokumenty.
      [ELSIF p->NAME=spam_protection]
        Je nutno chr�nit webov� archivy proti robot�m, kter� sb�raj� emailov� adresy.
        Jsou k dispozici r�zn� metody, kter� m��ete nastavit v parametrech spam_protection 
        a web_archive_spam_protection. Mo�n� hodnoty jsou:<BR><BR>
        <UL>
          <LI>javascript: adresa je schov�na pomoc� Javascriptu. U�ivatel, kter� m� aktivn� Javascript uvid� norm�ln� adresu, kde�to ostatn� neuvid� nic.
          <LI>at: znak "@" je nahrazen �et�zcem  " AT ".
          <LI>none : z�dn� ochrana proti spamer�m.
        </UL>
      [ELSIF p->NAME=subject]
        Tento parametru ur�uje sujekt zpr�vy, kter� je odesl�na jako odpov�� na p��kaz LISTS.
        Obsahem m��e b�t cokoliv v rozsahu jedn� ��dky
      [ELSIF p->NAME=subscribe]
        Parametr subscribe definuje pravidla pro p�ipojen� do konference.
        P�eddefinovan� sc�n��e jsou:<BR><BR>
        <UL>
          <LI>subscribe auth<BR>vy�adov�no potvrzen� po�avku na p�ihl�en�
          <LI>ubscribe auth_notify<BR>vy�adov�no potvrzen� (upozorn�n� je odesl�no spr�vc�m)
          <LI>subscribe auth_owner<BR>vy�aduje potvrzeni a pak schv�len� spr�vce
          <LI>subscribe closed<BR>nelze se p�ihl�sit
          <LI>subscribe intranet<BR>omezeno pouze pro lok�ln� u�ivatele
          <LI>subscribe intranetorowner<BR>omezeno pouze pro lok�ln� u�ivatele nebo potvrzen� spr�vce
          <LI>subscribe open<BR>pro kohokoliv bez potvrzen�
          <LI>subscribe open_notify<BR>kdokoli, upozorn�n� je odesl�no spr�vci
          <LI>subscribe open_quiet<BR>kdokoli, bez uv�tac� zpr�vy
          <LI>subscribe owner<BR>vy�adov�no sch�len� spr�vce
          <LI>subscribe smime<BR>vy�aduje S/MIME podpis
          <LI>subscribe smimeorowner<BR>vy�aduje S/MIME podpis nebo schv�len� spr�vce
        </UL>
      [ELSIF p->NAME=topics]
        Tento parametr dovoluje klasifikaci konferenc�. M��ete definovat v�ce t�mat nebo i jako hierarchii.
        Seznam ve�ejn�ch konferenci pro WWSympa pou�ije tuto hodnotu.
      [ELSIF p->NAME=ttl]
        Sympa si pamatuje data z�skan� z parametru include. Jejich doba �ivota (TTL) uvnit� Sympy
        se d� ovlivnit t�mto parametrem. V�choz� hodnota je 3600 vte�in.
      [ELSIF p->NAME=unsubscribe]
        Tento parametr ur�uje zp�sob odhla�ov�n� z konference. Pou�ijte volby open_notify nebo
        auth_notify pro zas�l�n� upozorn�n� spr�vci. P�eddefinovan� scen��e jsou:<BR><BR>
        <UL>
          <LI>unsubscribe auth<BR>vy�aduje autentizaci
          <LI>unsubscribe auth_notify<BR>vy�aduje autentizaci, zasl�no upozorn�ni spr�vci
          <LI>unsubscribe closed<BR>odhl�en� zak�z�no
          <LI>unsubscribe open<BR>kdokoliv bez autentizace
          <LI>unsubscribe open_notify<BR>bez autentizace, spr�vce obdr�� upozorn�n�
          <LI>unsubscribe owner<BR>vy�adov�no potvrzen� u�ivatele
        </UL>
      [ELSIF p->NAME=user_data_source]
        Sympa dovoluje definovat v�ce zdroj� pro seznam �len� konference.
        Tyto informace mohou b�t ulo�eny v textov�m souboru nebo v rela�n� datab�zi nebo
        vlo�eny z r�zn�ch extern�ch zdroj� (konference, prost� textov� soubor, dotaz do LDAP)
      [ELSIF p->NAME=visibility]
        Tento parametr ur�uje zda by se m�la konference zobrazovat ve v�stupu z p��kazu LISTS nebo
        by m�la b�t zobrazena v p�ehledu konferenc� na webov�m rozhran�.
      [ELSIF p->NAME=web_archive]
        Definuje kdo m��e p�istupovat do webov�ch arch�v� konference. P�eddefinovan� sc�n��e jsou:<BR><BR>
        <UL>
          <LI>access closed<BR>p��stup uzav�en
          <LI>access intranet<BR>omezen na u�ivatele z lok�ln� dom�ny
          <LI>access listmaster<BR>pouze spr�vce
          <LI>access owner<BR>pouze vlastn�k
          <LI>access private<BR>pouze �lenov� konference
          <LI>access public<BR>ve�ejn� p��stup
        </UL>
      [ELSIF p->NAME=web_archive_spam_protection]
        Podobn� jako polo�ka spam_protection ale omezeno na webov� arch�v. Dal�� hodnota je mo�n�: cookie -
        co� znamen�, �e u�ivatel� mus� proj�t mal�m formul��em, aby se dostali d�le k arch�v�m.
        Tato metoda blokuje v�echny roboty, v�etn� Google a pod.
      [ELSIF p->NAME=welcome_return_path]
        Pokud nastaveno na hodnotu to unique, bude uv�tac� zpr�va odeslana s unik�tn� n�vratovou adresou
        tak, aby se dal �len odstranit okam�it� v p��pad� vr�cen� zpr�vy.
      [ELSE]
        Bez koment��e
      [ENDIF]
    </DD>
  </DL>
[END]
