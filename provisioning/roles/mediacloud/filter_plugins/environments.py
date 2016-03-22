def get_envdict(ansible_dict):
    ''' input: an Ansible dictionary that contains environment variables
            in the stdout_lines, as for example, output of printenv '''
    return {t[0]:t[1] for t in [x.split('=') for x in ansible_dict.get('stdout_lines',[])]}

def add_envdict(ansible_dict, st):
    '''add a single environment variable declaration to a dictionary'''
    k,v = st.split('=')
    ansible_dict[k] = v
    return ansible_dict

class FilterModule(object):
     def filters(self):
         return {'getenvs': get_envdict,
                 'addenv': add_envdict,}
