package handlers

import "context"

func (s *Server) bumpTokenVersion(ctx context.Context, userID string) error {
	_, err := s.Pool.Exec(ctx,
		`UPDATE users SET token_version = token_version + 1, updated_at = now() WHERE id = $1`,
		userID)
	return err
}

func (s *Server) tokenVersionMatches(ctx context.Context, userID string, version int) bool {
	if s.Pool == nil {
		return true
	}
	var current int
	err := s.Pool.QueryRow(ctx, `SELECT token_version FROM users WHERE id = $1`, userID).Scan(&current)
	return err == nil && current == version
}
