package services_test

import (
	"testing"

	"github.com/keratin/authn-server/data/mock"
	"github.com/keratin/authn-server/services"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAccountArchiver(t *testing.T) {
	store := mock.NewAccountStore()

	account, err := store.Create("test@keratin.tech", []byte("password"))
	require.NoError(t, err)

	var testCases = []struct {
		account_id int
		errors     *[]services.Error
	}{
		{123456789, &[]services.Error{{"account", services.ErrNotFound}}},
		{account.Id, nil},
	}

	for _, tc := range testCases {
		errs := services.AccountArchiver(store, tc.account_id)
		if tc.errors == nil {
			assert.Empty(t, errs)
			acct, err := store.Find(tc.account_id)
			require.NoError(t, err)
			assert.Empty(t, acct.Username)
			assert.Empty(t, acct.Password)
			assert.NotEmpty(t, acct.DeletedAt)
		} else {
			assert.Equal(t, *tc.errors, errs)
		}
	}
}