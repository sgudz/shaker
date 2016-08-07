import ConfigParser
import base64
import json
import urllib2

parser = ConfigParser.SafeConfigParser()
parser.read('/root/env.conf')
fuel_ip = dict(parser.items('fuel'))['fuel_ip']
interface = dict(parser.items('fuel'))['interface']
create_new_run = dict(parser.items('testrail'))['create_new_run']
suite_id = dict(parser.items('testrail'))['suite_id']
cluster_id = dict(parser.items('fuel'))['cluster_id']
between_nodes = dict(parser.items('testrail'))['between_nodes']
version = str(dict(parser.items('fuel'))['version'])
print "create new run: {}".format(create_new_run)
if create_new_run == "true":
    print "suite_id: {}".format(suite_id)
# Testrail API
class APIClient:
    def __init__(self, base_url):
        self.user = ''
        self.password = ''
        if not base_url.endswith('/'):
            base_url += '/'
        self.__url = base_url + 'index.php?/api/v2/'

    def send_get(self, uri):
        return self.__send_request('GET', uri, None)

    def send_post(self, uri, data):
        return self.__send_request('POST', uri, data)

    def __send_request(self, method, uri, data):
        url = self.__url + uri
        request = urllib2.Request(url)
        if (method == 'POST'):
            request.add_data(json.dumps(data))
        auth = base64.b64encode('%s:%s' % (self.user, self.password))
        request.add_header('Authorization', 'Basic %s' % auth)
        request.add_header('Content-Type', 'application/json')

        e = None
        try:
            response = urllib2.urlopen(request).read()
        except urllib2.HTTPError as e:
            response = e.read()

        if response:
            result = json.loads(response)
        else:
            result = {}

        if e != None:
            if result and 'error' in result:
                error = '"' + result['error'] + '"'
            else:
                error = 'No additional error message received'
            raise APIError('TestRail API returned HTTP %s (%s)' %
                           (e.code, error))

        return result


class APIError(Exception):
    pass

client = APIClient('https://mirantis.testrail.com/')
client.user = 'sgudz@mirantis.com'
client.password = 'qwertY123'

def get_tests_ids():
    create_new_run = dict(parser.items('testrail'))['create_new_run']
    if create_new_run == "true":
        run_name = dict(parser.items('testrail'))['run_name']
        suite_id = int(dict(parser.items('testrail'))['suite_id'])
        data_str = """{"suite_id": %(suite_id)s, "name": "%(name)s", "assignedto_id": 89, "include_all": true}""" %{"suite_id": suite_id, "name": run_name}
        data = json.loads(data_str)
        result = client.send_post('add_run/3', data)
        run_id = result['id']
        tests = client.send_get('get_tests/{}'.format(run_id))
        tests_ids = []
        for item in tests:
            tests_ids.append(item['id'])
        return tests_ids
    else:
        run_id = dict(parser.items('testrail'))['run_id']
        tests = client.send_get('get_tests/{}'.format(run_id))
        tests_ids = []
        tests_dict = {}
        for item in tests:
            tests_ids.append(item['id'])
        return tests_ids

def get_token_id(fuel_ip):
    url='http://{}:5000/v2.0/tokens'.format(fuel_ip)
    headers={'Content-Type': 'application/json', 'Accept': 'application/json'}
    post_data = '{"auth": {"tenantName": "admin", "passwordCredentials": {"username": "admin", "password": "admin"}}}'
    req = urllib2.Request(url,data=post_data, headers=headers)
    content = urllib2.urlopen(req)
    json_data = json.load(content)
    return json_data['access']['token']['id']

def get_neutron_conf(fuel_ip, token_id):
    headers = {'X-Auth-Token': token_id}
    url = 'http://{0}:8000/api/clusters/{1}/network_configuration/neutron'.format(fuel_ip,cluster_id)
    req = urllib2.Request(url, headers=headers)
    content = urllib2.urlopen(req)
    json_data = json.load(content)
    return json_data

def get_nodes(fuel_ip, token_id):
    headers = {'X-Auth-Token': token_id}
    url = 'http://{0}:8000/api/nodes/?cluster_id={1}'.format(fuel_ip, cluster_id)
    req = urllib2.Request(url, headers=headers)
    content = urllib2.urlopen(req)
    nodes_data = json.load(content)
    nodes_list = [item['id'] for item in nodes_data]
    return nodes_list

def get_cluster_attributes(fuel_ip, token_id):
    headers = {'X-Auth-Token': token_id}
    url = 'http://{0}:8000/api/clusters/{1}/attributes'.format(fuel_ip, cluster_id)
    req = urllib2.Request(url, headers=headers)
    content = urllib2.urlopen(req)
    attributes_data = json.load(content)
    return attributes_data

def get_computes(fuel_ip, token_id):
    headers = {'X-Auth-Token': token_id}
    compute_ids = []
    for node in get_nodes(fuel_ip, token_id):
        url = 'http://{0}:8000/api/nodes/{1}'.format(fuel_ip, node)
        req = urllib2.Request(url, headers=headers)
        content = urllib2.urlopen(req)
        nodes_data = json.load(content)
        if 'compute' in nodes_data['roles']:
            compute_ids.append(node)
    return compute_ids

def get_offloading(fuel_ip, token_id):
    headers = {'X-Auth-Token': token_id}
    offloading_nodes = {}
    for node in get_nodes(fuel_ip, token_id):
        url = 'http://{0}:8000/api/nodes/{1}/interfaces'.format(fuel_ip, node)
        req = urllib2.Request(url, headers=headers)
        content = urllib2.urlopen(req)
        interface_data = json.load(content)
        for item in interface_data:
            if item['name'] == interface:
                interface_data = item
        state_list = []
        for item in interface_data['offloading_modes']:
            state_list.append(item['state'])
        for item in state_list:
            if item is None:
                state = "Default"
            elif not item:
                state = False
            else:
                state = True
            offloading_nodes["Node-" + str(node)] = state
    return offloading_nodes
token_id = get_token_id(fuel_ip)
