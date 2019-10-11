# docker-postgres
docker-postgres provides a simple way to create a docker image for postgres that includes the following:
* Three default roles for access (admin, read_write, and read_only)
* Two schemas, one for base tables and one for audit tables
* Template table with standard columns
* Functions to use for quickly implementing audit triggers

## Usage
### Create Docker Image
Begin by creating the docker image. This is a basic docker command that you can alter to meet your needs. Specifically
you may name the image as you wish. In the example we name the image "appdb."

```
docker build -t appdb .
```

### Start Container
After creating the image, you will next start the docker container. Again, you can customize this command to your liking.
Specifically you may wish to change the port mappings. Also, you can set the following parameters that affect database
creation:
* POSTGRES_DB -- this is the name of the database you wish to create
* POSTGRES_PASSWORD -- this is the password that will be assigned to the "postgres" superuser that will be created

```
docker run --name appdb -e POSTGRES_DB=dbname -e POSTGRES_PASSWORD=test_password -p 15432:5432 -d appdb
```

### Connect to Database
You can now connect to the database via psql or any other tool of your choosing. We recommend only connecting via
the "postgres" superuser to create other users with more granular permissions. See below for more instructions about users
and roles.

```
psql --host localhost --username postgres --port 15432 dbname --password
```

## Schemas
The container creates two schemas: base and audit. The base schema is set as part of the search_path, so the
intent is that the base representation of any table is stored in the base schema and a structurally similar table
is created in the audit schema so that any modifications to data in the base schema can be recorded in the
audit schema as well.

See below for more instructions on how to create base and audit tables and for how to trigger changes from
one to the other.

## Template table
A template table called "template" is created in the base schema with the following columns:
* orig_insert_ts -- timestamp of the original insert of the row; should never be modified after insert; this value is automatically set
* last_change_ts -- timestamp of the last modification to the row; this value is automatically set
* app_last_change_by -- user id of the application user who made the last modification to the row; this value is up to the developer to provide
* db_last_change_by -- user id of the database user who made the last modification to the row; this value is automatically set

## Create table example
Let's look at how we would create a base and audit table for a sample table with a single "name" column of type
text. We'll call our table "sample." To do this we would execute the following:

```sql
set role admin;

CREATE TABLE sample (
  id SERIAL NOT NULL PRIMARY KEY,
  LIKE template INCLUDING ALL,
  name text null
);

CREATE TRIGGER sample_last_change_trigger
  BEFORE UPDATE
  ON sample
  FOR EACH ROW
 EXECUTE PROCEDURE update_last_change();

CREATE TABLE audit.sample (
  aud_id SERIAL NOT NULL PRIMARY KEY,
  aud_op TEXT   NOT NULL,
  LIKE sample EXCLUDING ALL
);

CREATE TRIGGER sample_audit_change_trigger
  AFTER INSERT OR UPDATE OR DELETE
  ON sample
  FOR EACH ROW
EXECUTE PROCEDURE audit_change();
```

The above creates two tables: base.sample and audit.sample as well as two triggers. The first trigger records
the last change information for time and user who last updated the row. The second trigger saves a copy of the
row in the audit table any time a row is inserted, updated or deleted in the base table.

The audit table will be created with the same structure as the base table and with two additional columns:
* aud_id -- the primary key of the audit row itself
* aud_op -- one of INSERT, UPDATE, or DELETE to indicate the operation that was audited

Note that at the beginning of the script, we set the role to admin. This must be done so that the table is created
under the admin role and the correct default permissions are applied. If the table is not created under the admin
role, other users may not have appropriate access to the table unless you have specifically updated the default
privileges for the user creating the table.

## Users and Roles
The container creates three roles. The only user with login access that is created is the "postgres" superuser. 
You can log in with this user to create other users with login access as follows.

### admin
Users with the "admin" role are granted the ability to manage schema structure, including creating and dropping
tables, indexes, functions, and triggers. They are also granted access to modify data within the schemas.

You create "admin" users for only those users who need this level of access. Namely, if you are connecting
an application that simply needs to read or read/write data within a pre-defined schema, you should use
a different role.

To create an admin user called "app_admin" with password 'test_password' you would execute the following:

```sql
create user app_admin in role admin password 'test_password';
```

Obviously, the command can be modified to include additional options per the Postgres documentation.

### read_write
Users with the "read_write" role are granted the ability to read and write data from the schemas but are
not granted the ability to modify schema structure. Create users in this role for users who simply need
read and write access to the schemas. This role is ideal for an application user that simply needs to connect
to a pre-defined schema to read and write data.

To create a read_write user called "app_user" with password 'test_password' you would execute the following:

```sql
create user app_user in role read_write password 'test_password';
```

### read_only
Users with the "read_only" role are granted read-only access to the schemas and have no ability to modify data
or schema structure. This is ideal for users who should not be able to make changes, for example for users
who may need to have view access to production data but without the risk of potentially modifying data or structure.

To create a read_only user called "app_read" with password 'test_password' you would execute the following:

```sql
create user app_read in role read_only password 'test_password';
```