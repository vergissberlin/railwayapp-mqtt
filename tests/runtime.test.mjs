import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';

const image = process.env.MQTT_TEST_IMAGE || 'railwayapp-mqtt:test';
const docker = (...args) => execFileSync('docker', args, {encoding: 'utf8', timeout: 120000, stdio: ['ignore', 'pipe', 'pipe']}).trim();
const password = 'runtime-test-only';
const credentials = ['-u', 'tester', '-P', password];
const waitForBroker = async (container, auth) => {
    for (let attempt = 0; attempt < 40; attempt++) {
        try {
            docker('exec', container, 'mosquitto_pub', '-h', 'localhost', ...auth, '-t', 'healthcheck', '-m', 'ping');
            return;
        } catch {
            await new Promise(resolve => setTimeout(resolve, 250));
        }
    }
    assert.fail(`Broker did not start: ${docker('logs', container)}`);
};
const runHealthcheck = container => {
    const command = JSON.parse(docker('image', 'inspect', image, '--format', '{{json .Config.Healthcheck.Test}}'));
    assert.equal(command[0], 'CMD-SHELL');
    docker('exec', container, 'sh', '-c', command[1]);
};

test('authenticated broker retains data on a root-owned volume and survives restart', async () => {
    const name = `mqtt-test-${randomUUID()}`;
    const volume = `${name}-data`;
    docker('volume', 'create', volume);
    try {
        docker('run', '-d', '--name', name, '-e', 'MQTT_USER=tester', '-e', `MQTT_PASS=${password}`, '-v', `${volume}:/mosquitto/data`, image);
        await waitForBroker(name, credentials);
        runHealthcheck(name);
        assert.throws(() => docker('exec', name, 'mosquitto_pub', '-h', 'localhost', '-t', 'denied', '-m', 'ping'));
        assert.equal(docker('exec', name, 'stat', '-c', '%U:%a', '/mosquitto/config/passwordfile'), 'mosquitto:600');
        assert.equal(docker('exec', name, 'stat', '-c', '%U', '/mosquitto/data'), 'mosquitto');
        docker('exec', name, 'mosquitto_pub', '-h', 'localhost', ...credentials, '-t', 'persisted', '-m', 'survived', '-r');
        docker('restart', name);
        await waitForBroker(name, credentials);
        runHealthcheck(name);
        assert.equal(docker('exec', name, 'mosquitto_sub', '-h', 'localhost', ...credentials, '-t', 'persisted', '-C', '1', '-W', '5'), 'survived');
    } finally {
        docker('rm', '-f', name);
        docker('volume', 'rm', volume);
    }
});

test('anonymous local broker starts and its healthcheck succeeds without credentials', async () => {
    const name = `mqtt-test-${randomUUID()}`;
    try {
        docker('run', '-d', '--name', name, '--tmpfs', '/mosquitto/data', image);
        await waitForBroker(name, []);
        runHealthcheck(name);
    } finally {
        docker('rm', '-f', name);
    }
});
