# 🔍 User Registration Error Guide

## ❌ "User Failed to Create" Error

This error occurs when user registration fails. The most common causes are:

---

## 🔐 Password Requirements

Your API has **simple password requirements** for easy account creation:

### Required Password Rules:
- ✅ **Minimum 4 characters**
- ✅ Any characters allowed (letters, numbers, special characters - all optional)

### ✅ Valid Password Examples:
- `farm`
- `mypassword`
- `1234`
- `pass`
- Any password with at least 4 characters

---

## 📋 Required Fields

All these fields are **required** for registration:

1. ✅ **FarmName** - Name of your farm
2. ✅ **Username** - Unique username
3. ✅ **Email** - Valid email address (must be unique)
4. ✅ **Password** - Must meet all requirements above
5. ✅ **FirstName** - User's first name
6. ✅ **LastName** - User's last name
7. ⚠️ **PhoneNumber** - Optional but recommended
8. ⚠️ **Roles** - Optional (defaults to empty array)

---

## 🐛 Common Registration Errors

### 1. Password Too Short
**Error**: Password doesn't meet requirements

**Solution**: 
- Use at least 4 characters
- Any password with 4 or more characters will work
- Example: `farm` or `mypassword`

### 2. Email Already Exists
**Error**: "User already exists!"

**Solution**: 
- Use a different email address
- Or login with existing account

### 3. Invalid Email Format
**Error**: Email validation failed

**Solution**: 
- Use valid email format: `user@example.com`
- No spaces or special characters in wrong places

### 4. Missing Required Fields
**Error**: Field validation failed

**Solution**: 
- Ensure all required fields are provided:
  - FarmName
  - Username
  - Email
  - Password
  - FirstName
  - LastName

### 5. Database Connection Error
**Error**: Connection string issues

**Solution**: 
- Check `appsettings.json` connection string
- Verify database server is accessible
- Check firewall rules

---

## 🧪 Test Registration Request

### Valid Registration Example:

```json
{
  "farmName": "My Poultry Farm",
  "username": "farmowner",
  "email": "owner@farm.com",
  "password": "mypassword",
  "firstName": "John",
  "lastName": "Doe",
  "phoneNumber": "+1234567890",
  "roles": ["User"]
}
```

### Test in Postman:

1. **URL**: `POST https://usermanagementapi.poultrycore.com/api/Authentication/Register`
2. **Headers**: 
   - `Content-Type: application/json`
3. **Body** (raw JSON):
```json
{
  "farmName": "Test Farm",
  "username": "testuser123",
  "email": "test@example.com",
  "password": "testpass",
  "firstName": "Test",
  "lastName": "User",
  "phoneNumber": "+1234567890",
  "roles": ["User"]
}
```

---

## 🔧 Improved Error Messages

I've updated the code to show **detailed error messages** instead of just "User Failed to Create". 

The new error response will show:
- Which password requirement failed
- Which field is missing
- Specific validation errors

---

## ✅ Registration Success Response

When registration succeeds, you'll get:

```json
{
  "isSuccess": true,
  "statusCode": 200,
  "message": "User and Farm Created {email sent message}",
  "response": {
    "user": { ... },
    "token": "email-confirmation-token"
  }
}
```

---

## 🚀 Quick Fix Checklist

- [ ] Password is at least 4 characters
- [ ] Email is valid and unique
- [ ] Username is provided
- [ ] FarmName is provided
- [ ] FirstName is provided
- [ ] LastName is provided

---

## 📞 Need Help?

If registration still fails after checking all requirements:

1. **Check the error message** - It should now show specific validation errors
2. **Test in Postman** - Use the example above
3. **Check server logs** - Look for detailed error messages
4. **Verify database connection** - Ensure connection string is correct

---

**The error handling has been improved to show specific validation errors!** 🎉

