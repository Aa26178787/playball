-- 회원탈퇴(DELETE FROM users) 시 개인정보 완전 삭제 + FK 위반으로 탈퇴 실패하던 문제 교정.
-- 기존: posts/comments/post_likes/push_tokens/user_settings/user_favorite_*/notifications 가
--       users FK에 NO ACTION → 해당 행 있는 유저는 탈퇴가 FK 위반으로 실패 + 개인정보 잔존.
-- 추가로 posts→comments, posts→post_likes 도 NO ACTION 이라 글 삭제 연쇄도 불완전.
-- 정책: 개인 데이터(글/댓글/좋아요/설정/즐겨찾기/토큰/알림) = CASCADE 삭제(완전 erasure).
--       맛집 제보(stadium_food_places.submitted_by) = SET NULL(커뮤니티 데이터 보존, 제보자 익명화).
BEGIN;

-- users 참조 FK → CASCADE
ALTER TABLE posts                 DROP CONSTRAINT posts_user_id_fkey,
  ADD CONSTRAINT posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE comments              DROP CONSTRAINT comments_user_id_fkey,
  ADD CONSTRAINT comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE post_likes            DROP CONSTRAINT post_likes_user_id_fkey,
  ADD CONSTRAINT post_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE notifications         DROP CONSTRAINT notifications_user_id_fkey,
  ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE push_tokens           DROP CONSTRAINT push_tokens_user_id_fkey,
  ADD CONSTRAINT push_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE user_settings         DROP CONSTRAINT user_settings_user_id_fkey,
  ADD CONSTRAINT user_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE user_favorite_players DROP CONSTRAINT user_favorite_players_user_id_fkey,
  ADD CONSTRAINT user_favorite_players_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE user_favorite_teams   DROP CONSTRAINT user_favorite_teams_user_id_fkey,
  ADD CONSTRAINT user_favorite_teams_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- posts 참조 child FK → CASCADE (글 삭제 시 댓글/좋아요 연쇄)
ALTER TABLE comments              DROP CONSTRAINT comments_post_id_fkey,
  ADD CONSTRAINT comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
ALTER TABLE post_likes            DROP CONSTRAINT post_likes_post_id_fkey,
  ADD CONSTRAINT post_likes_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;

-- 맛집 제보자 → SET NULL (장소는 보존, 제보자만 익명화)
ALTER TABLE stadium_food_places ALTER COLUMN submitted_by DROP NOT NULL;
ALTER TABLE stadium_food_places   DROP CONSTRAINT stadium_food_places_submitted_by_fkey,
  ADD CONSTRAINT stadium_food_places_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES users(id) ON DELETE SET NULL;

COMMIT;
