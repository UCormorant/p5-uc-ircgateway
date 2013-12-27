CREATE TABLE 'user_backup' AS SELECT * FROM 'user';

DROP TABLE 'user';

CREATE TABLE 'user' (
  'login'          text NOT NULL,
  'nick'           text NOT NULL,
  'password'       text NOT NULL DEFAULT '',
  'realname'       text NOT NULL DEFAULT '*',
  'host'           text NOT NULL DEFAULT 'localhost',
  'addr'           text NOT NULL DEFAULT '*',
  'server'         text NOT NULL DEFAULT 'localhost',

  'userinfo'       text,
  'away_message'   text,
  'last_modified'  int NOT NULL DEFAULT (strftime('%s', 'now')),

  'away'           boolean NOT NULL DEFAULT 0,
  'invisible'      boolean NOT NULL DEFAULT 0,
  'allow_wallops'  boolean NOT NULL DEFAULT 0,
  'restricted'     boolean NOT NULL DEFAULT 0,
  'operator'       boolean NOT NULL DEFAULT 0,
  'local_operator' boolean NOT NULL DEFAULT 0,
  'allow_s_notice' boolean NOT NULL DEFAULT 0,

  PRIMARY KEY ('login')
);
CREATE UNIQUE INDEX 'nick_index' ON 'user' ('nick');

INSERT OR IGNORE INTO 'user' (
    'login',
    'nick',
    'password',
    'realname',
    'host',
    'addr',
    'server',

    'userinfo',
    'away_message',
    'last_modified',

    'away',
    'invisible',
    'allow_wallops',
    'restricted',
    'operator',
    'local_operator',
    'allow_s_notice'
) SELECT * FROM 'user_backup';

DROP TABLE 'user_backup';
