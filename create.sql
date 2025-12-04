CREATE USER SISTEMA IDENTIFIED BY SISTEMA;
GRANT CONNECT, RESOURCE TO SISTEMA;

ALTER USER SISTEMA QUOTA 30M ON USERS;

-- Criar sequencia de clientes
CREATE SEQUENCE SISTEMA.SEQ_CLIENTE START WITH 1 NOCYCLE NOCACHE;

-- Criar tabela de clientes
create table SISTEMA.TB_CLIENTE
(
  id_cliente     NUMBER not null,
  nome           VARCHAR2(100) not null,
  email          VARCHAR2(100),
  cep            VARCHAR2(8),
  logradouro     VARCHAR2(100),
  bairro         VARCHAR2(100),
  cidade         VARCHAR2(100),
  uf             CHAR(2),
  ativo          INTEGER default 1,
  dt_criacao     DATE default SYSDATE,
  dt_atualizacao DATE
) tablespace USERS;

-- Comentando algumas colunas, demais são explicativas  
comment on column SISTEMA.TB_CLIENTE.id_cliente is 'Chave primaria da tabela.';
comment on column SISTEMA.TB_CLIENTE.ativo is 'Indica se o cliente esta ativo (1) ou nao (0).';

-- Criação das constraints
-- PK da tabela
alter table SISTEMA.TB_CLIENTE add primary key (ID_CLIENTE) using index tablespace USERS;
-- Restricao de email unico  
alter table SISTEMA.TB_CLIENTE add constraint CNT_CLIENTE_EMAIL unique (EMAIL) using index tablespace USERS;
-- Restricao de UF valida
alter table SISTEMA.TB_CLIENTE add constraint CNT_CLIENTE_UF_CK
  check (UF in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'));

-- Trigger de before insert/update para tratamento de PK e data de atualização
CREATE OR REPLACE TRIGGER SISTEMA.TRG_CLIENTE_AUDIT 
       BEFORE INSERT OR UPDATE ON SISTEMA.TB_CLIENTE
       FOR EACH ROW 
BEGIN
  if :new.id_cliente is null then
     :new.id_cliente := sistema.seq_cliente.nextval;
  end if;
  if updating then 
    :new.dt_atualizacao := SYSDATE;
  end if;
EXCEPTION
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20001, 'Ocorreu um erro na atualizacao do registro' || substr(sqlerrm,1,500));
END;  
/  

-- Tabela Log de Erro
create table SISTEMA.TB_LOG_ERRO
(
  dt_evento  DATE,
  usuario    VARCHAR2(30),
  origem     VARCHAR2(100),
  mensagem   VARCHAR2(1000),
  tipo       VARCHAR2(3),
  formulario VARCHAR2(100),
  bloco      VARCHAR2(100),
  instancia  VARCHAR2(100)
) tablespace USERS;

CREATE OR REPLACE PACKAGE SISTEMA.PKG_CLIENTE AS
  ---------------------------------------------------------------------------------------------
  -- Criado em: 01/12/2025
  -- Finalidade: Projeto XXXX
  -- Criado por: Will Silva
  -- Funcionalidades:
  -- FN_VALIDAR_EMAIL: Verificar se o email informado e valido
  -- FN_NORMALIZAR_CEP: Quando informado, retornar apenas digitos, 8 posicoes
  -- PRC_DELETAR_CLIENTE: Excluir cliente de ID informado no parametro
  -- PRC_LISTAR_CLIENTES: Listar todos os clientes que atendem os filtros informados
  ---------------------------------------------------------------------------------------------
  FUNCTION FN_VALIDAR_EMAIL(p_email VARCHAR2) RETURN NUMBER;
  FUNCTION FN_NORMALIZAR_CEP(p_cep VARCHAR2) RETURN VARCHAR2;
  PROCEDURE PRC_DELETAR_CLIENTE(p_id NUMBER);
  PROCEDURE PRC_LISTAR_CLIENTES(p_nome VARCHAR2, p_email VARCHAR2, p_rc OUT SYS_REFCURSOR);
  PROCEDURE PRC_GRAVA_ERRO(p_erro tb_log_erro%rowtype);
END PKG_CLIENTE;
/

CREATE OR REPLACE PACKAGE BODY SISTEMA.PKG_CLIENTE AS
  ---------------------------------------------------------------------------------------------
  -- FN_VALIDAR_EMAIL: Verificar se o email informado e valido
  ---------------------------------------------------------------------------------------------
  FUNCTION FN_VALIDAR_EMAIL(p_email VARCHAR2) RETURN NUMBER IS
  BEGIN
    IF REGEXP_LIKE(p_email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') THEN
      RETURN 1;
    ELSE
      RETURN 0;
    END IF;
  END FN_VALIDAR_EMAIL;
  ---------------------------------------------------------------------------------------------
  -- FN_NORMALIZAR_CEP: Quando informado, retornar apenas digitos, 8 posicoes
  ---------------------------------------------------------------------------------------------
  FUNCTION FN_NORMALIZAR_CEP(p_cep VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF p_cep IS NOT NULL THEN
      RETURN lpad(regexp_replace(p_cep,'[^[:digit:]]',''),8,'0');
    ELSE
      RETURN NULL;
    END IF;
  END FN_NORMALIZAR_CEP;
  ---------------------------------------------------------------------------------------------
  -- PRC_DELETAR_CLIENTE: Excluir cliente de ID informado no parametro
  ---------------------------------------------------------------------------------------------
  PROCEDURE PRC_DELETAR_CLIENTE(p_id NUMBER) AS
    v_count integer;
  BEGIN
    -- Validar se o ID informado e valido
    IF NVL(p_id,0) = 0 THEN
       raise_application_error(-20002, 'O ID informado esta invalido.');
       RETURN;
    END IF;
    --
    -- Verificar se o registro existe no banco de dados
    SELECT count(*) into v_count FROM sistema.tb_cliente
     WHERE id_cliente = p_id;
    -- Se nao existir, retornar erro. Existindo: efetuar exclusao e commit;
    IF v_count = 0 THEN
       raise_application_error(-20003, 'Cliente ' || p_id || ' nao encontrado na base de dados.');
       RETURN;
    ELSE
       DELETE FROM sistema.tb_cliente WHERE id_cliente = p_id;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
    IF SQLCODE BETWEEN -20999 AND -20000 THEN
       RAISE;
    ELSE
      raise_application_error(-20004, 'Nao foi possivel efetuar a exclusao. Motivo: ' || substr(SQLERRM,1,500));
    END IF;
  END;
  ---------------------------------------------------------------------------------------------
  -- PRC_LISTAR_CLIENTES: Listar todos os clientes que atendem os filtros informados
  ---------------------------------------------------------------------------------------------
  PROCEDURE PRC_LISTAR_CLIENTES(p_nome VARCHAR2, p_email VARCHAR2, p_rc OUT SYS_REFCURSOR) IS
  BEGIN
    OPEN p_rc FOR
    SELECT * FROM sistema.tb_cliente
     WHERE (p_nome IS NULL OR lower(nome) LIKE '%' || lower(p_nome) || '%')
       AND (p_email IS NULL OR lower(email) LIKE '%' || lower(p_email) || '%');
  END PRC_LISTAR_CLIENTES;
  ---------------------------------------------------------------------------------------------
  -- PRC_GRAVA_ERRO: Salvar os erros da aplicação
  ---------------------------------------------------------------------------------------------
  PROCEDURE PRC_GRAVA_ERRO(p_erro tb_log_erro%rowtype) IS
  BEGIN
    insert into sistema.tb_log_erro
    (dt_evento, usuario, origem, mensagem, tipo, formulario, bloco, instancia)
  values
    (p_erro.dt_evento, p_erro.usuario, p_erro.origem, p_erro.mensagem, p_erro.tipo, p_erro.formulario, p_erro.bloco, p_erro.instancia);
  COMMIT; 
  EXCEPTION
     -- Caso nao seja possivel gravar o erro, continuar o fluxo
     WHEN OTHERS THEN NULL;         
  END PRC_GRAVA_ERRO;  
END PKG_CLIENTE;
/

-------------------------------------------------------------------------------------------------
-- Testes de funcionalidade da package PKG_CLIENTE
-- Não executar em PRODUCAO: Vai apagar todos os dados da tabela TB_CLIENTE
-------------------------------------------------------------------------------------------------
TRUNCATE TABLE SISTEMA.TB_CLIENTE;

-- TST001 Retorna 1 - Verdadeiro
SELECT SISTEMA.PKG_CLIENTE.FN_VALIDAR_EMAIL('emailvalido@email.com') FROM dual;
-- TST002 Retorna 0 - Falso
SELECT SISTEMA.PKG_CLIENTE.FN_VALIDAR_EMAIL('emailinvalido@email.x') FROM dual;

-- TST003 Retorna um CEP com 8 digitos
SELECT SISTEMA.PKG_CLIENTE.FN_NORMALIZAR_CEP('A102030X@') FROM dual;
-- TST004 Retorna nulo quando nao informado
SELECT SISTEMA.PKG_CLIENTE.FN_NORMALIZAR_CEP('') FROM dual;

-- Criando massa de testes para validar procedure que retorna Pesquisa e exclusão de clientes
-- Uso do COPILOT para gerar a massa de testes
INSERT INTO SISTEMA.TB_CLIENTE
(id_cliente, nome, email, cep, logradouro, bairro, cidade, uf, ativo, dt_criacao, dt_atualizacao)
VALUES (NULL, 'Ana Silva', 'ana.silva01@gmail.com', '01001000', 'Rua das Flores, 123', 'Centro', 'São Paulo', 'SP', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Carlos Pereira', 'carlos.pereira@yahoo.com', '20040002', 'Av. Atlântica, 456', 'Copacabana', 'Rio de Janeiro', 'RJ', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Mariana Souza', 'mariana.souza@hotmail.com', '30140071', 'Rua da Bahia, 789', 'Funcionários', 'Belo Horizonte', 'MG', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'João Oliveira', 'joao.oliveira@gmail.com', '40020000', 'Rua Chile, 321', 'Comércio', 'Salvador', 'BA', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Fernanda Costa', 'fernanda.costa@outlook.com', '60060110', 'Av. Beira Mar, 654', 'Meireles', 'Fortaleza', 'CE', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Ricardo Lima', 'ricardo.lima@gmail.com', '70040900', 'Esplanada dos Ministérios, Bloco A', 'Zona Cívico-Administrativa', 'Brasília', 'DF', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Paula Mendes', 'paula.mendes@gmail.com', '80010020', 'Rua XV de Novembro, 987', 'Centro', 'Curitiba', 'PR', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Felipe Rocha', 'felipe.rocha@gmail.com', '90010120', 'Av. Borges de Medeiros, 654', 'Centro Histórico', 'Porto Alegre', 'RS', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Camila Martins', 'camila.martins@gmail.com', '95010000', 'Rua das Hortênsias, 321', 'Centro', 'Caxias do Sul', 'RS', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Thiago Almeida', 'thiago.almeida@gmail.com', '96010120', 'Av. Bento Gonçalves, 456', 'Fragata', 'Pelotas', 'RS', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Juliana Ferreira', 'juliana.ferreira@gmail.com', '97010000', 'Rua do Acampamento, 789', 'Centro', 'Santa Maria', 'RS', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Bruno Santos', 'bruno.santos@gmail.com', '88010020', 'Av. Beira Mar Norte, 123', 'Centro', 'Florianópolis', 'SC', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Patrícia Gomes', 'patricia.gomes@gmail.com', '64010020', 'Av. Frei Serafim, 456', 'Centro', 'Teresina', 'PI', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Rodrigo Nunes', 'rodrigo.nunes@gmail.com', '69005010', 'Av. Eduardo Ribeiro, 789', 'Centro', 'Manaus', 'AM', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Larissa Carvalho', 'larissa.carvalho@gmail.com', '66010020', 'Av. Nazaré, 321', 'Nazaré', 'Belém', 'PA', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Gabriel Teixeira', 'gabriel.teixeira@gmail.com', '58010020', 'Av. Epitácio Pessoa, 654', 'Tambauzinho', 'João Pessoa', 'PB', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Isabela Ramos', 'isabela.ramos@gmail.com', '79002020', 'Av. Afonso Pena, 987', 'Centro', 'Campo Grande', 'MS', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Daniel Barbosa', 'daniel.barbosa@gmail.com', '74010020', 'Av. Goiás, 123', 'Setor Central', 'Goiânia', 'GO', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Sofia Azevedo', 'sofia.azevedo@gmail.com', '65010020', 'Av. Pedro II, 456', 'Centro', 'São Luís', 'MA', 1, SYSDATE, NULL);

INSERT INTO SISTEMA.TB_CLIENTE
VALUES (NULL, 'Lucas Moreira', 'lucas.moreira@gmail.com', '78010020', 'Av. Getúlio Vargas, 789', 'Centro', 'Cuiabá', 'MT', 1, SYSDATE, NULL);

COMMIT;

-- TST005 Retorna erro -20004 ao tentar deletar um registro inexistente
BEGIN
  SISTEMA.PKG_CLIENTE.PRC_DELETAR_CLIENTE(1000);
END;
/

-- TST006 Bloco que retorna apenas os registros validos: Retorna IDs 8 e 14
SET SERVEROUTPUT ON;
DECLARE
    v_rc   SYS_REFCURSOR;
    v_rec_cliente SISTEMA.TB_CLIENTE%ROWTYPE;
BEGIN
    -- Chama a procedure passando parâmetros
    SISTEMA.PKG_CLIENTE.PRC_LISTAR_CLIENTES(p_nome => 'RO', p_email => NULL, p_rc => v_rc);
    -- Percorre os resultados
    LOOP
        FETCH v_rc INTO v_rec_cliente;
        EXIT WHEN v_rc%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(v_rec_cliente.id_cliente || ' - ' || v_rec_cliente.nome || ' - ' || v_rec_cliente.email);
    END LOOP;
    CLOSE v_rc;
END;
/

-- TST007 Exclusao de um registro que existe: sem retorno
BEGIN
  SISTEMA.PKG_CLIENTE.PRC_DELETAR_CLIENTE(8);
END;
/

-- TST008 Bloco que retorna apenas os registros validos: Após exclusão, Retorna apenas ID 14
-- Repetir teste TST006 

-- TST009 Restricao de email unico: Retorna ORA-00001: restrição exclusiva (SISTEMA.CNT_CLIENTE_EMAIL) violada
INSERT INTO SISTEMA.TB_CLIENTE
(id_cliente, nome, email, cep, logradouro, bairro, cidade, uf, ativo, dt_criacao, dt_atualizacao)
VALUES (NULL, 'Adriana Silva', 'ana.silva01@gmail.com', '01001000', 'Rua das Flores, 123', 'Centro', 'São Paulo', 'SP', 1, SYSDATE, NULL);

-- TST010 Restricao de UF valida: Retorna ORA-02290: restrição de verificação (SISTEMA.CNT_CLIENTE_UF_CK) violada
INSERT INTO SISTEMA.TB_CLIENTE
(id_cliente, nome, email, cep, logradouro, bairro, cidade, uf, ativo, dt_criacao, dt_atualizacao)
VALUES (NULL, 'Adriana Silva', 'adriana.silva01@gmail.com', '01001000', 'Rua das Flores, 123', 'Centro', 'São Paulo', 'XP', 1, SYSDATE, NULL);
