#!/usr/bin/env python3
from __future__ import print_function

import os
import re
import sys
import subprocess

parse_begin_pattern = vt_convert_src_pattern = "backends/v2v/cfg/convert_source.cfg"
parse_end_pattern = "python-virtinst"
vt_convert_dst_pattern = "backends/v2v/cfg/convert_destination.cfg"

tp_libvirt_specific_kvm_pattern = "v2v/tests/cfg/specific_kvm.cfg"
tp_libvirt_v2v_options_pattern = "v2v/tests/cfg/v2v_options.cfg"
tp_libvirt_func_test_xen_pattern = "v2v/tests/cfg/function_test_xen.cfg"
tp_libvirt_func_test_esx_pattern = "v2v/tests/cfg/function_test_esx.cfg"
tp_libvirt_convert_file_pattern = "v2v/tests/cfg/convert_from_file.cfg"

all_pattern = "v2v/tests/cfg/.*.cfg"

vt_src = {}
vt_dst = {}
specific_kvm = {}
v2v_option= {}
func_xen = {}
func_esx = {}
convert_file = {}
all_cfg = {}

all_pattern_dict = {vt_convert_src_pattern:vt_src,
               vt_convert_dst_pattern:vt_dst,
               tp_libvirt_v2v_options_pattern:v2v_option,
               tp_libvirt_convert_file_pattern:convert_file,
               tp_libvirt_specific_kvm_pattern:specific_kvm,
               tp_libvirt_func_test_esx_pattern:func_esx,
               tp_libvirt_func_test_xen_pattern:func_xen,
               all_pattern:all_cfg}

def print_help():
    print('Usage:\n\t%s %s %s ...' % (sys.argv[0],
          '$path_to/libvirt_ci/jobs.yaml',
          '$path_to_tp-libvirt_cfg_files'))
    print('arg1 is file path to libvirt_ci jobs.yaml')
    print('arg2 arg3 ... is file path or directory to tp-libvirt cfg files')

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print_help()
        sys.exit(1)

    if os.path.exists(sys.argv[1]):
        jobs_yaml = sys.argv[1]
    else:
        print('Error: jobs_yaml file %s does not exist' % sys.argv[1])
        sys.exit(1)
    cfg_files = []
    for i in range(2, len(sys.argv)):
        if os.path.isfile(sys.argv[i]):
            cfg_files.append(sys.argv[i])
        elif os.path.isdir(sys.argv[i]):
            for x, _, z in os.walk(sys.argv[i]):
                [cfg_files.append(os.path.join(x, f_i)) for f_i in z if f_i.endswith('.cfg')]
        else:
            print("Warning: %s doesn't exist" % sys.argv[i])

    if len(cfg_files) == 0:
        print('Not speficy cfg files, Nothing to do')
        sys.exit(0)

    begin_flag = False
    cur_ptn = None
    with open(jobs_yaml) as fp:
        for line in fp:
            if not begin_flag:
                if not re.search(parse_begin_pattern, line):
                    continue
                else:
                    begin_flag = True

            if '-->' in line and cur_ptn:
                tmp_list = line.strip().split('-->')
                all_pattern_dict[cur_ptn][tmp_list[0].strip(' "\'')] = tmp_list[1].strip(' "\'')
            else:
                for ptn in all_pattern_dict.keys():
                    if re.search(ptn, line):
                        cur_ptn = ptn

            if re.search(parse_end_pattern, line):
                break

    for set_i in all_pattern_dict.items():
        for cfg_i in cfg_files:
            if re.search(set_i[0], cfg_i):
                print('Match cfg file %s with pattern[%s]' % (cfg_i, set_i[0]))
                for it in set_i[1].items():
                    cmd = ['sed', '-i', 's/{0}/{1}/g'.format(it[0].strip(' \'"'), it[1].strip(' \'"').replace('/','\/')), cfg_i]
                    #cmd = 'sed -i s/%s/%s/g %s' % (it[0].strip('\'"'), it[1].strip('\'"'), cfg_i)
                    ret = subprocess.run(cmd)
                    if ret.returncode != 0:
                        print('FAIL: %s --> %s' % it)
