<?php
/**
 * Deploy config for yoxa.eu (production) and test.yoxa.eu (test).
 *
 * Based on the official deployer shopware recipe; project-specific parts:
 * - shared `.env` (server config lives there)
 * - host('production-server') / host('test-server') aliases
 * - plugin install/activate on deploy
 */

namespace Deployer;

require_once 'recipe/common.php';

add('recipes', ['shopware']);

set('bin/console', '{{bin/php}} {{release_or_current_path}}/bin/console');

// Shopware 6.7 requires PHP >= 8.2; the webhost default (/usr/bin/php) is 8.1
set('bin/php', getenv('WEBHOST_PHP') ?: '/usr/bin/php83');

set('default_timeout', 3600); // Increase when tasks take longer than that.

// Always remove a stale deploy lock left over from a previous failed deploy
before('deploy', 'deploy:unlock');

set('repository', 'git@github.com:xavgru12/ShopwareServer.git');

// Production: yoxa.eu — deploy with `dep deploy production-server`
host('production-server')
    ->setHostname(getenv('HOST') ?: 'w01a5092.kasserver.com')
    ->setRemoteUser(getenv('USERNAME') ?: 'ssh-w01a5092')
    ->set('deploy_path', '/www/htdocs/w01a5092/ShopwareServer')
    ->set('writable_mode', 'chmod');

// Test: test.yoxa.eu — deploy with `dep deploy test-server`
host('test-server')
    ->setHostname(getenv('HOST') ?: 'w01a5092.kasserver.com')
    ->setRemoteUser(getenv('USERNAME') ?: 'ssh-w01a5092')
    ->set('deploy_path', '/www/htdocs/w01a5092/TestShop')
    ->set('writable_mode', 'chmod');

// These files are shared among all releases.
set('shared_files', [
    '.env',
    'install.lock',
    'public/.htaccess',
    'public/.user.ini',
]);

// These directories are shared among all releases.
set('shared_dirs', [
    'config/jwt',
    'files',
    'var/log',
    'public/media',
    'public/plugins',
    'public/thumbnail',
    'public/sitemap',
]);

// These directories are made writable (the definition of "writable" requires attention).
// Please note that the files in `config/jwt/*` receive special attention in the `sw:writable:jwt` task.
set('writable_dirs', [
    'config/jwt',
    'custom/plugins',
    'files',
    'public/bundles',
    'public/css',
    'public/fonts',
    'public/js',
    'public/media',
    'public/plugins',
    'public/sitemap',
    'public/theme',
    'public/thumbnail',
    'var',
]);

// This sets the Shopware version to the version of the Shopware console command.
set('shopware_version', function () {
    $versionOutput = run('cd {{release_path}} && {{bin/console}} -V');
    preg_match('/(\d+\.\d+\.\d+\.\d+)/', $versionOutput, $matches);
    return $matches[0] ?? '6.6.0';
});

// This task remotely executes the `cache:clear` console command on the target server.
task('sw:cache:clear', static function () {
    run('cd {{release_path}} && {{bin/console}} cache:clear --no-warmup');
});

// This task remotely executes the cache warmup console commands on the target server, so that the first user, who
// visits the website, doesn't have to wait for the cache to be built up.
task('sw:cache:warmup', static function () {
    run('cd {{release_path}} && {{bin/console}} cache:warmup');

    // Shopware 6.6+ dropped support for the http:cache:warmup command, so only execute it if the version is less than 6.6
    if (version_compare(get('shopware_version'), '6.6.0') < 0) {
        run('cd {{release_path}} && {{bin/console}} http:cache:warm:up');
    }
});

// This task remotely executes the `database:migrate` console command on the target server.
task('sw:database:migrate', static function () {
    run('cd {{release_path}} && {{bin/console}} database:migrate --all');
});

task('sw:plugin:refresh', function () {
    run('cd {{release_path}} && {{bin/console}} plugin:refresh');
});

task('sw:scheduled-task:register', function () {
    run('cd {{release_path}} && {{bin/console}} scheduled-task:register');
});

task('sw:theme:refresh', function () {
    run('cd {{release_path}} && {{bin/console}} theme:refresh');
});

// This task is not used by default, but can be used, e.g. in combination with `SHOPWARE_SKIP_THEME_COMPILE=1`,
// to build the theme remotely instead of locally.
task('sw:theme:compile', function () {
    run('cd {{release_path}} && {{bin/console}} theme:compile');
});

function getPlugins(): array
{
    $output = run('cd {{release_path}} && {{bin/console}} plugin:list --json');
    $plugins = json_decode($output);

    return $plugins;
}

task('sw:plugin:install:all', static function () {
    foreach (getPlugins() as $plugin) {
        if (!$plugin->installedAt) {
            writeln("<info>Running plugin install for " . $plugin->name . "</info>\n");
            run("cd {{release_path}} && {{bin/console}} plugin:install --activate " . $plugin->name);
        }
    }
});

task('sw:plugin:update:all', static function () {
    foreach (getPlugins() as $plugin) {
        if ($plugin->installedAt && $plugin->upgradeVersion) {
            writeln("<info>Running plugin update for " . $plugin->name . "</info>\n");
            run("cd {{release_path}} && {{bin/console}} plugin:update " . $plugin->name);
        }
    }
});

task('sw:writable:jwt', static function () {
    if (!test('[ -d {{deploy_path}}/config/jwt/ ]')) {
        return;
    }
    run('cd {{release_path}} && find config/jwt/ -type f -exec chmod -R 660 {} +');
});

set('license_host', 'yoxa.eu'); // domain registered in the Shopware Account for store/app licensing

task('sw:app:install', static function () {
    run('cd {{release_path}} && {{bin/console}} system:config:set core.store.licenseHost {{license_host}}');
    if (!test('cd {{release_path}} && {{bin/console}} app:list | grep -q StripePaymentsApp')) {
        run('cd {{release_path}} && {{bin/console}} app:install --activate --force StripePaymentsApp');
    } else {
        run('cd {{release_path}} && {{bin/console}} app:refresh StripePaymentsApp');
    }
});

/**
 * Grouped SW deploy tasks.
 */
task('sw:deploy', [
    'sw:database:migrate',
    'sw:plugin:refresh',
    'sw:theme:refresh',
    'sw:theme:compile',
    'sw:scheduled-task:register',
    'sw:app:install',
    'sw:cache:clear',
    'sw:plugin:install:all',
    'sw:plugin:update:all',
    'sw:cache:clear',
]);

desc('Deploys your project');
task('deploy', [
    'deploy:prepare',
    'sw:writable:jwt',
    'sw:deploy',
    'deploy:clear_paths',
    'sw:cache:warmup',
    'deploy:publish',
]);

task('deploy:update_code')->setCallback(static function () {
    upload('.', '{{release_path}}', [
        'options' => [
            '--exclude=.git',
            '--exclude=deploy.php',
            '--exclude=node_modules',
        ],
    ]);
});

task('sw-build-without-db:get-remote-config', static function () {
    if (!test('[ -d {{current_path}} ]')) {
        return;
    }
    // Copy .env files into build directory so we don't default to APP_ENV=dev and APP_DEBUG=1 during build
    download("{{current_path}}/", "./", [
        "options" => ["--copy-links", "--include=.env*", "--exclude=*"],
    ]);
    within('{{current_path}}', function () {
        run('{{bin/php}} ./bin/console bundle:dump');
        download('{{current_path}}/var/plugins.json', './var/');

        run('{{bin/php}} ./bin/console theme:dump -n');
        download('{{current_path}}/files/theme-config', './files/');
    });
});

task('sw-build-without-db:build', static function () {
    runLocally('CI=1 SHOPWARE_SKIP_BUNDLE_DUMP=1 SHOPWARE_SKIP_THEME_COMPILE=1 bin/build-js.sh');
});

task('sw-build-without-db', [
    'sw-build-without-db:get-remote-config',
    'sw-build-without-db:build',
]);

// Disabled: requires Node on the runner/local machine and downloads the
// server's .env* into the local build dir. Storefront assets ship prebuilt
// and the theme compiles server-side via sw:theme:compile.
// before('deploy:update_code', 'sw-build-without-db');
