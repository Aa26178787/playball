// 홈 셸(HomeScreen)이 등록하는 탭 뒤로가기 핸들러.
// OS 뒤로가기(웹 JS 트랩 installWebBackHandler / 네이티브 didPopRoute)가
// 팝할 라우트가 없을 때 호출 → 이전 탭으로 이동(이동했으면 true, 히스토리 없으면 false).
// (#2 — 웹/네이티브 뒤로가기가 무조건 홈탭으로 가던 문제: 탭 전환은 라우트가 아니라
//  Navigator 백이 잡지 못함 → 셸이 자체 탭 히스토리로 처리)
bool Function()? appTabBackHandler;
