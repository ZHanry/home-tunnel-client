// HOMEDESK: 测试身份复用、无默认服务和撤权，不启动真实子进程或访问公网。
import 'dart:convert';
import '../../client/flutter/lib/homedesk_local_agent.dart';
import '../../client/flutter/lib/homedesk_tunnel_api.dart';

const localId = '11111111-1111-4111-8111-111111111111';
void check(bool value, String message) { if (!value) throw StateError(message); }

class Account extends HomeTunnelApi {
  int enrollments = 0;
  bool registered = false;
  Account() : super('https://control.example.invalid', isAllowed: () => true);
  @override String get userId => '22222222-2222-4222-8222-222222222222';
  @override Future<String> createEnrollmentCode(String name) async {
    enrollments++;
    return 'synthetic-single-use-enrollment-code';
  }
  @override Future<HomeTunnelCatalog> catalog() async => HomeTunnelCatalog(
    devices: registered ? [const HomeTunnelDevice(id:localId,name:'本机',platform:'windows',online:true)] : [],
    services: []);
}

Future<void> main() async {
  final api = Account();
  var view = <String,dynamic>{};
  var allowed = true;
  var stamp = '1';
  var runs = 0;
  var forceUnknown = false;
  final actions = <String>[];
  Future<void> send(String value) async {
    final command = jsonDecode(value) as Map<String,dynamic>;
    actions.add(command['action'] as String);
    view = {'owner':command['owner'],'device_id':api.registered ? localId : '', 'agent_state':'Starting'};
    switch (command['action']) {
      case 'inspect': view['phase'] = forceUnknown ? 'error' : api.registered ? 'registered' : 'needs_enrollment';
        if (forceUnknown) view['code'] = 'ENROLLMENT_RESULT_UNKNOWN';
        break;
      case 'enroll': api.registered = true; view.addAll({'phase':'registered','device_id':localId}); break;
      case 'run': runs++; view['phase']='running'; break;
      case 'stop': view['phase']='stopped'; break;
    }
  }
  HomeDeskLocalAgent controller() => HomeDeskLocalAgent(send:send,read:()=>jsonEncode(view),
    permission:()=>stamp,isAllowed:()=>allowed,name:'本机');
  final first = controller();
  final catalog = await first.attach(api, await api.catalog());
  check(catalog.devices.length==1 && catalog.services.isEmpty, '登记一台设备且不创建服务');
  check(api.enrollments==1 && runs==1, '一次接入码和一次运行');
  await first.attach(api, catalog);
  check(api.enrollments==1 && runs==1, '相同实例不重复接入');
  await first.stop();
  final reopened = controller();
  await reopened.attach(api, await api.catalog());
  check(api.enrollments==1 && runs==2, '重开复用设备，不创建重复设备');
  await reopened.stop();
  final wrongAccount = controller();
  try {
    await wrongAccount.attach(api, HomeTunnelCatalog(devices:[],services:[]));
    throw StateError('不应运行其他账号的设备');
  } on HomeDeskAgentException catch (error) { check(error.code=='DEVICE_OUTSIDE_ACCOUNT','拒绝所属账号不符'); }
  forceUnknown=true;
  final uncertain = controller();
  try {
    await uncertain.attach(api, await api.catalog());
    throw StateError('不应重放未知登记');
  } on HomeDeskAgentException catch (error) { check(error.code=='ENROLLMENT_RESULT_UNKNOWN','未知结果停止'); }
  check(api.enrollments==1, '未知结果没有新接入码');
  allowed=false; stamp='2';
  final revoked = controller();
  try {
    await revoked.attach(api, await api.catalog());
    throw StateError('撤权后不能接入');
  } on HomeDeskAgentException catch (error) { check(error.code=='PERMISSION_CHANGED','撤权前拒绝进程命令'); }
  check(runs==2, '撤权未运行新进程');
  api.close();
  print('本机 Agent：首次登记、零默认服务、重开复用、账号隔离、未知结果与撤权检查通过。');
}
