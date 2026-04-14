<?php
// configs/wordpress/wp-config.php
// WordPress конфигурация с Memcached для сессий + DB master

define('DB_NAME', 'wordpress');
define('DB_USER', 'wpuser');
define('DB_PASSWORD', 'WpPassword2026Strong!');
define('DB_HOST', '127.0.0.1');        // на master — локально, на slave можно оставить (но лучше master)
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

define('AUTH_KEY',         'put your unique phrases here');
define('SECURE_AUTH_KEY',  'put your unique phrases here');
define('LOGGED_IN_KEY',    'put your unique phrases here');
define('NONCE_KEY',        'put your unique phrases here');
define('AUTH_SALT',        'put your unique phrases here');
define('SECURE_AUTH_SALT', 'put your unique phrases here');
define('LOGGED_IN_SALT',   'put your unique phrases here');
define('NONCE_SALT',       'put your unique phrases here');

$table_prefix = 'wp_';

define('WP_DEBUG', false);

// Memcached для объектного кэша и сессий
define('WP_CACHE', true);
define('WP_CACHE_KEY_SALT', 'wp_');
$memcached_servers = array(
    array('127.0.0.1', 11211),   // master
    array('192.168.88.167', 11211) // slave (если нужно)
);

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', dirname( __FILE__ ) . '/' );
}

require_once ABSPATH . 'wp-settings.php';
